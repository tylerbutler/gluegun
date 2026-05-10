import gleam/dynamic
import gleam/list
import gleam/result
import gleam/string
import gluegun/internal.{type Connection, type Stream}

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

pub fn headers(options: RequestOptions) -> List(Header) {
  options.headers
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

/// Send an HTTP request on an open Gun connection.
pub fn request(
  connection: Connection,
  method: Method,
  path: String,
  headers: List(Header),
  body: BitArray,
  options: RequestOptions,
) -> Stream {
  ffi_request(
    internal.connection_raw(connection),
    method_to_string(method),
    path,
    normalize_headers(list.append(headers, options.headers)),
    body,
    options_to_ffi(options),
  )
  |> internal.stream
}

/// Stream request body data for a request.
pub fn data(
  connection: Connection,
  stream: Stream,
  fin: anything,
  data: BitArray,
) {
  ffi_data(
    internal.connection_raw(connection),
    internal.stream_raw(stream),
    fin_to_ffi(fin),
    data,
  )
  |> result.map(fn(_) { Nil })
}

/// Cancel a request stream.
pub fn cancel(connection: Connection, stream: Stream) {
  ffi_cancel(internal.connection_raw(connection), internal.stream_raw(stream))
  |> result.map(fn(_) { Nil })
}

/// Flush Gun messages for a connection.
pub fn flush(connection: Connection) {
  ffi_flush(internal.connection_raw(connection))
  |> result.map(fn(_) { Nil })
}

fn options_to_ffi(_options: RequestOptions) -> dynamic.Dynamic {
  dynamic.properties([])
}

fn fin_to_ffi(fin) -> dynamic.Dynamic {
  unsafe_coerce(fin)
}

@external(erlang, "gleam_stdlib", "identity")
fn unsafe_coerce(a: anything) -> dynamic.Dynamic

@external(erlang, "gluegun_ffi", "request")
fn ffi_request(
  connection: dynamic.Dynamic,
  method: String,
  path: String,
  headers: List(Header),
  body: BitArray,
  options: dynamic.Dynamic,
) -> dynamic.Dynamic

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

@external(erlang, "gluegun_ffi", "flush")
fn ffi_flush(
  connection: dynamic.Dynamic,
) -> Result(dynamic.Dynamic, dynamic.Dynamic)
