//// Low-level HTTP request and stream operations.
////
//// Use this module when you need Gun stream references, chunked request
//// bodies, flow-control updates, cancellation, or direct access to asynchronous
//// Gun messages. For simple full-body responses, prefer `gluegun/client`.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gluegun/connection.{type Connection}
import gluegun/error
import gluegun/fin.{type Fin}
import gluegun/internal

/// HTTP request method constructors.
///
/// Use canonical constructors such as `Get`, `Post`, and `Put`, or `Custom`
/// for extension methods.
pub type Method {
  /// HTTP `GET`. Safe and idempotent.
  Get
  /// HTTP `HEAD`. Same as `Get` but the response has no body.
  Head
  /// HTTP `POST`. Create or submit data; not idempotent.
  Post
  /// HTTP `PUT`. Replace the target resource; idempotent.
  Put
  /// HTTP `PATCH`. Apply a partial modification.
  Patch
  /// HTTP `DELETE`. Remove the target resource; idempotent.
  Delete
  /// HTTP `OPTIONS`. Describe communication options for the target.
  Options
  /// HTTP `TRACE`. Loop-back diagnostics; rarely used.
  Trace
  /// HTTP `CONNECT`. Establish a tunnel through a proxy.
  Connect
  /// An extension or non-standard method. The wrapped string is sent verbatim.
  Custom(String)
}

/// HTTP header represented as `#(name, value)`.
pub type Header =
  #(String, String)

/// Opaque handle for a Gun request stream.
pub type Stream =
  internal.Stream

/// Request options passed through the low-level request API.
///
/// Build with `options()` then chain `with_headers` or `add_headers` for
/// option-level headers. Use `with_initial_flow` for finite response credit.
pub opaque type RequestOptions {
  RequestOptions(headers: List(Header), initial_flow: Option(Int))
}

/// Typed Gun request options for the FFI boundary.
@internal
pub type RequestOption {
  InitialFlow(Int)
}

/// Construct default request options.
pub fn options() -> RequestOptions {
  RequestOptions(headers: [], initial_flow: None)
}

/// Add option-level headers that are appended to per-call headers.
pub fn add_headers(
  options: RequestOptions,
  headers headers: List(Header),
) -> RequestOptions {
  RequestOptions(..options, headers: list.append(options.headers, headers))
}

/// Replace option-level headers.
pub fn with_headers(
  options: RequestOptions,
  headers headers: List(Header),
) -> RequestOptions {
  RequestOptions(..options, headers: headers)
}

/// Set finite initial response credit in data messages, not bytes.
///
/// Credit must be positive. One permits a data message before `update_flow`.
/// Headers do not consume credit. Gun can parse several HTTP chunks or HTTP/2
/// frames from one socket read before it pauses, so credit is not a strict
/// mailbox-message or allocation limit. Check each chunk's byte size before
/// retaining it. With no setting, Gun keeps its unlimited default.
/// Use `message.await` and replenish credit yourself. Full-body collectors
/// such as `message.await_body` and `client.send` do not replenish it.
pub fn with_initial_flow(
  options: RequestOptions,
  credit credit: Int,
) -> Result(RequestOptions, error.GluegunError) {
  case credit > 0 {
    True -> Ok(RequestOptions(..options, initial_flow: Some(credit)))
    False -> Error(error.InvalidOptions("initial flow credit must be positive"))
  }
}

@internal
pub fn options_to_ffi(options: RequestOptions) -> List(RequestOption) {
  case options.initial_flow {
    Some(credit) -> [InitialFlow(credit)]
    None -> []
  }
}

/// Inspect option-level headers.
@internal
pub fn headers_option(options: RequestOptions) -> List(Header) {
  options.headers
}

/// Convert a method constructor to its HTTP method string.
pub fn method_to_string(method: Method) -> String {
  case method {
    Get -> "GET"
    Head -> "HEAD"
    Post -> "POST"
    Put -> "PUT"
    Patch -> "PATCH"
    Delete -> "DELETE"
    Options -> "OPTIONS"
    Trace -> "TRACE"
    Connect -> "CONNECT"
    Custom(method) -> method
  }
}

/// Lowercase header names without changing values.
///
/// This helper does not validate names. Pass original headers to `request` or
/// `start_stream`, which validate ASCII tokens before lowercasing names.
@internal
pub fn normalize_headers(headers: List(Header)) -> List(Header) {
  list.map(headers, fn(header) {
    let #(name, value) = header
    #(string.lowercase(name), value)
  })
}

/// Send a low-level HTTP request on an open Gun connection.
///
/// Returns a stream reference; response messages are delivered asynchronously
/// to the calling process (unless Gun options redirect replies). Use
/// `gluegun/message.await` / `await_body` to consume them, or use
/// `gluegun/client` helpers to collect a regular response.
///
/// The method, path, and headers are validated before crossing to Gun: the
/// method and path must be non-empty and must not contain a control byte,
/// space, or DEL (including CR/LF); original header names must be valid ASCII
/// HTTP tokens before they are lowercased;
/// header values must not contain a control byte (other than HTAB) or DEL;
/// and headers cannot include a caller-supplied `Transfer-Encoding` or a
/// duplicate/malformed `Content-Length`. Invalid input returns
/// `InvalidOptions` instead of reaching Gun.
///
/// The body must contain whole bytes. A non-byte-aligned `BitArray` returns
/// `InvalidOptions` before Gun receives the request. Empty bodies are valid.
///
/// Errors: `ConnectionDown`, `StreamError`, `InvalidOptions`.
pub fn request(
  connection: Connection,
  method: Method,
  path: String,
  headers: List(Header),
  body: BitArray,
  options: RequestOptions,
) -> Result(Stream, error.GluegunError) {
  ffi_request(
    connection,
    method_to_string(method),
    path,
    list.append(headers, options.headers),
    body,
    options_to_ffi(options),
  )
}

/// Start a low-level HTTP request whose body will be streamed in chunks.
///
/// Send zero or more body chunks with `data(..., fin.NoFin, ...)`, then
/// terminate the request with a final `data(..., fin.Fin, ...)` (which may
/// carry an empty `BitArray` if there is no trailing payload). The stream
/// remains open for response messages either way.
///
/// Gun response messages go to the calling process. `with_initial_flow`
/// sets response credit before Gun starts the stream.
///
/// The method, path, and headers are validated the same way as `request`;
/// see its documentation for the rejected shapes.
///
/// Errors: `ConnectionDown`, `StreamError`, `InvalidOptions`.
pub fn start_stream(
  connection: Connection,
  method: Method,
  path: String,
  headers: List(Header),
  options: RequestOptions,
) -> Result(Stream, error.GluegunError) {
  ffi_headers(
    connection,
    method_to_string(method),
    path,
    list.append(headers, options.headers),
    options_to_ffi(options),
  )
}

/// Send a chunk of request body data on an open stream.
///
/// Pass `fin.NoFin` for intermediate chunks and `fin.Fin` for the last
/// chunk. After sending the final chunk the request body is closed, but the
/// stream remains open for response messages.
///
/// Chunks must contain whole bytes; empty chunks are valid. A
/// non-byte-aligned `BitArray` returns `InvalidOptions` without sending data
/// or closing the request body, even when `fin.Fin` is supplied.
pub fn data(
  connection: Connection,
  stream: Stream,
  fin: Fin,
  data: BitArray,
) -> Result(Nil, error.GluegunError) {
  ffi_data(connection, stream, fin, data)
}

/// Cancel an in-flight request stream.
///
/// Sends a reset/cancel to Gun. The connection remains usable for new
/// streams. Pending response messages for the cancelled stream may still
/// arrive briefly and should be drained.
pub fn cancel(
  connection: Connection,
  stream: Stream,
) -> Result(Nil, error.GluegunError) {
  ffi_cancel(connection, stream)
}

/// Update HTTP/1.1 or HTTP/2 stream flow control by the given increment.
///
/// The increment must be positive. Gun rejects non-positive flow-control
/// increments, so this function validates the value before crossing the FFI
/// boundary and returns `InvalidOptions` for zero or negative increments.
/// The unit is data messages for both HTTP/1.1 and HTTP/2, not bytes.
/// Finite credit pauses socket reads in HTTP/1.1 and stream window updates
/// in HTTP/2. It does not bound bytes in a message or data already buffered.
pub fn update_flow(
  connection: Connection,
  stream: Stream,
  increment: Int,
) -> Result(Nil, error.GluegunError) {
  case increment > 0 {
    True -> ffi_update_flow(connection, stream, increment)
    False ->
      Error(error.InvalidOptions("flow-control increment must be positive"))
  }
}

/// Discard buffered Gun messages currently queued for the calling process.
///
/// Useful after `cancel` or when recovering from an aborted flow. Returns
/// `Ok(Nil)` even when no messages were buffered.
/// It does not prevent late arrivals. Use `connection.terminate` to stop the
/// sender, wait for exit, and flush this caller's connection messages.
pub fn flush(connection: Connection) -> Result(Nil, error.GluegunError) {
  ffi_flush(connection)
}

@external(erlang, "gluegun_ffi", "headers")
fn ffi_headers(
  connection: Connection,
  method: String,
  path: String,
  headers: List(Header),
  options: List(RequestOption),
) -> Result(Stream, error.GluegunError)

@external(erlang, "gluegun_ffi", "request")
fn ffi_request(
  connection: Connection,
  method: String,
  path: String,
  headers: List(Header),
  body: BitArray,
  options: List(RequestOption),
) -> Result(Stream, error.GluegunError)

@external(erlang, "gluegun_ffi", "data")
fn ffi_data(
  connection: Connection,
  stream: Stream,
  fin: Fin,
  data: BitArray,
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ffi", "cancel")
fn ffi_cancel(
  connection: Connection,
  stream: Stream,
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ffi", "update_flow")
fn ffi_update_flow(
  connection: Connection,
  stream: Stream,
  increment: Int,
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ffi", "flush")
fn ffi_flush(connection: Connection) -> Result(Nil, error.GluegunError)
