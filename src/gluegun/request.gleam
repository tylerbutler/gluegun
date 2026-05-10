import gleam/list
import gleam/string

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
  RequestOptions(headers: List(Header))
}

pub fn request_options() -> RequestOptions {
  RequestOptions(headers: [])
}

pub fn with_headers(
  _options: RequestOptions,
  headers headers: List(Header),
) -> RequestOptions {
  RequestOptions(headers: headers)
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
