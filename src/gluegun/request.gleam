//// Low-level HTTP request and stream operations.
////
//// Use this module when you need Gun stream references, chunked request
//// bodies, flow-control updates, cancellation, or direct access to asynchronous
//// Gun messages. For simple full-body responses, prefer `gluegun/client`.

import gleam/dynamic
import gleam/list
import gleam/string
import gluegun/connection.{type Connection}
import gluegun/error
import gluegun/fin.{type Fin}
import gluegun/internal
import gluegun/internal/ffi_result

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
/// option-level headers that apply to every call.
pub opaque type RequestOptions {
  RequestOptions(headers: List(Header))
}

/// Construct default request options.
pub fn options() -> RequestOptions {
  RequestOptions(headers: [])
}

/// Add option-level headers that are appended to per-call headers.
pub fn add_headers(
  options: RequestOptions,
  headers headers: List(Header),
) -> RequestOptions {
  RequestOptions(headers: list.append(options.headers, headers))
}

/// Replace option-level headers.
pub fn with_headers(
  _options: RequestOptions,
  headers headers: List(Header),
) -> RequestOptions {
  RequestOptions(headers: headers)
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

/// Lowercase header names for the Erlang Gun FFI boundary without changing values.
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
    internal.connection_raw(connection),
    method_to_string(method),
    path,
    normalize_headers(list.append(headers, options.headers)),
    body,
    options_to_ffi(options),
  )
  |> ffi_result.decode_request_result
}

/// Start a low-level HTTP request whose body will be streamed in chunks.
///
/// Send zero or more body chunks with `data(..., fin.NoFin, ...)`, then
/// terminate the request with a final `data(..., fin.Fin, ...)` (which may
/// carry an empty `BitArray` if there is no trailing payload). The stream
/// remains open for response messages either way.
///
/// Gun response messages are delivered to the calling process by default;
/// pass an option to redirect via Gun's `reply_to` if you need another
/// process to consume them.
///
/// Errors: `ConnectionDown`, `StreamError`, `InvalidOptions`.
pub fn start_stream(
  connection: Connection,
  method: Method,
  path: String,
  headers: List(Header),
  options: RequestOptions,
) -> Result(Stream, error.GluegunError) {
  let #(method, path, headers, options) =
    headers_args_to_ffi(method, path, headers, options)

  ffi_headers(
    internal.connection_raw(connection),
    method,
    path,
    headers,
    options,
  )
  |> ffi_result.decode_request_result
}

/// Send a chunk of request body data on an open stream.
///
/// Pass `fin.NoFin` for intermediate chunks and `fin.Fin` for the last
/// chunk. After sending the final chunk the request body is closed, but the
/// stream remains open for response messages.
pub fn data(
  connection: Connection,
  stream: Stream,
  fin: Fin,
  data: BitArray,
) -> Result(Nil, error.GluegunError) {
  ffi_data(
    internal.connection_raw(connection),
    internal.stream_raw(stream),
    fin,
    data,
  )
  |> ffi_result.decode_nil_result
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
  ffi_cancel(internal.connection_raw(connection), internal.stream_raw(stream))
  |> ffi_result.decode_nil_result
}

/// Update HTTP/1.1 or HTTP/2 stream flow control by the given increment.
///
/// The increment must be positive. Gun rejects non-positive flow-control
/// increments, so this function validates the value before crossing the FFI
/// boundary and returns `InvalidOptions` for zero or negative increments.
pub fn update_flow(
  connection: Connection,
  stream: Stream,
  increment: Int,
) -> Result(Nil, error.GluegunError) {
  case increment > 0 {
    True -> {
      let #(connection, stream, increment) =
        update_flow_args_to_ffi(connection, stream, increment)

      ffi_update_flow(connection, stream, increment)
      |> ffi_result.decode_nil_result
    }
    False ->
      Error(error.InvalidOptions("flow-control increment must be positive"))
  }
}

/// Discard buffered Gun messages currently queued for the calling process.
///
/// Useful after `cancel` or when recovering from an aborted flow. Returns
/// `Ok(Nil)` even when no messages were buffered.
pub fn flush(connection: Connection) -> Result(Nil, error.GluegunError) {
  ffi_flush(internal.connection_raw(connection))
  |> ffi_result.decode_nil_result
}

fn options_to_ffi(_options: RequestOptions) -> dynamic.Dynamic {
  dynamic.properties([])
}

@internal
pub fn headers_args_to_ffi(
  method: Method,
  path: String,
  headers: List(Header),
  options: RequestOptions,
) -> #(String, String, List(Header), dynamic.Dynamic) {
  #(
    method_to_string(method),
    path,
    normalize_headers(list.append(headers, options.headers)),
    options_to_ffi(options),
  )
}

@internal
pub fn fin_to_ffi(fin: Fin) -> dynamic.Dynamic {
  ffi_fin_to_ffi(fin)
}

@external(erlang, "gluegun_ffi", "fin_to_ffi")
fn ffi_fin_to_ffi(fin: Fin) -> dynamic.Dynamic

@internal
pub fn update_flow_args_to_ffi(
  connection: Connection,
  stream: Stream,
  increment: Int,
) -> #(dynamic.Dynamic, dynamic.Dynamic, Int) {
  #(internal.connection_raw(connection), internal.stream_raw(stream), increment)
}

@external(erlang, "gluegun_ffi", "headers")
fn ffi_headers(
  connection: dynamic.Dynamic,
  method: String,
  path: String,
  headers: List(Header),
  options: dynamic.Dynamic,
) -> Result(dynamic.Dynamic, dynamic.Dynamic)

@external(erlang, "gluegun_ffi", "request")
fn ffi_request(
  connection: dynamic.Dynamic,
  method: String,
  path: String,
  headers: List(Header),
  body: BitArray,
  options: dynamic.Dynamic,
) -> Result(dynamic.Dynamic, dynamic.Dynamic)

@external(erlang, "gluegun_ffi", "data")
fn ffi_data(
  connection: dynamic.Dynamic,
  stream: dynamic.Dynamic,
  fin: Fin,
  data: BitArray,
) -> Result(dynamic.Dynamic, dynamic.Dynamic)

@external(erlang, "gluegun_ffi", "cancel")
fn ffi_cancel(
  connection: dynamic.Dynamic,
  stream: dynamic.Dynamic,
) -> Result(dynamic.Dynamic, dynamic.Dynamic)

@external(erlang, "gluegun_ffi", "update_flow")
fn ffi_update_flow(
  connection: dynamic.Dynamic,
  stream: dynamic.Dynamic,
  increment: Int,
) -> Result(dynamic.Dynamic, dynamic.Dynamic)

@external(erlang, "gluegun_ffi", "flush")
fn ffi_flush(
  connection: dynamic.Dynamic,
) -> Result(dynamic.Dynamic, dynamic.Dynamic)
