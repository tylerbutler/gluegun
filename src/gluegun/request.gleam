import gleam/dynamic
import gleam/erlang/atom
import gleam/list
import gleam/string
import gluegun/error
import gluegun/internal.{type Connection, type Stream}
import gluegun/internal/ffi_result
import gluegun/message

pub type Method {
  Get
  Head
  Post
  Put
  Patch
  Delete
  Options
  Trace
  Connect
  Custom(String)
}

pub type Header =
  #(String, String)

pub opaque type RequestOptions {
  RequestOptions(headers: List(Header), reserved: Nil)
}

pub fn request_options() -> RequestOptions {
  RequestOptions(headers: [], reserved: Nil)
}

pub fn with_headers(
  options: RequestOptions,
  headers headers: List(Header),
) -> RequestOptions {
  RequestOptions(..options, headers: headers)
}

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
pub fn normalize_headers(headers: List(Header)) -> List(Header) {
  list.map(headers, fn(header) {
    let #(name, value) = header
    #(string.lowercase(name), value)
  })
}

/// Send a low-level HTTP request on an open Gun connection.
///
/// This returns a stream reference. Use `gluegun/client` helpers to collect a
/// regular HTTP response into a `Response`.
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

/// Start a low-level HTTP request whose body will be streamed later.
///
/// The caller must send request body chunks with `data(..., NoFin, ...)` and
/// complete the request with `data(..., Fin, ...)`. Gun response messages go to
/// the calling process by default unless Gun request options redirect replies.
pub fn headers(
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

/// Stream request body data for a request.
pub fn data(
  connection: Connection,
  stream: Stream,
  fin: message.Fin,
  data: BitArray,
) -> Result(Nil, error.GluegunError) {
  ffi_data(
    internal.connection_raw(connection),
    internal.stream_raw(stream),
    fin_to_ffi(fin),
    data,
  )
  |> ffi_result.decode_nil_result
}

/// Cancel a request stream.
pub fn cancel(
  connection: Connection,
  stream: Stream,
) -> Result(Nil, error.GluegunError) {
  ffi_cancel(internal.connection_raw(connection), internal.stream_raw(stream))
  |> ffi_result.decode_nil_result
}

/// Update HTTP/1.1 or HTTP/2 stream flow control by the given increment.
pub fn update_flow(
  connection: Connection,
  stream: Stream,
  increment: Int,
) -> Result(Nil, error.GluegunError) {
  let #(connection, stream, increment) =
    update_flow_args_to_ffi(connection, stream, increment)

  ffi_update_flow(connection, stream, increment)
  |> decode_update_flow_result
}

/// Flush Gun messages for a connection.
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
pub fn fin_to_ffi(fin: message.Fin) -> dynamic.Dynamic {
  case fin {
    message.Fin -> atom.to_dynamic(atom.create("fin"))
    message.NoFin -> atom.to_dynamic(atom.create("nofin"))
  }
}

@internal
pub fn update_flow_args_to_ffi(
  connection: Connection,
  stream: Stream,
  increment: Int,
) -> #(dynamic.Dynamic, dynamic.Dynamic, Int) {
  #(internal.connection_raw(connection), internal.stream_raw(stream), increment)
}

@internal
pub fn decode_update_flow_result(
  result: Result(dynamic.Dynamic, dynamic.Dynamic),
) -> Result(Nil, error.GluegunError) {
  ffi_result.decode_nil_result(result)
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
  fin: dynamic.Dynamic,
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
