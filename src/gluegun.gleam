/// Main module for gluegun.
///
/// gluegun is a Gleam wrapper for the Erlang Gun HTTP client.
import gluegun/connection.{
  type ConnectOptions, type Protocol, type Timeout, type Transport,
}
import gluegun/request.{type Header, type Method, type RequestOptions}
import gluegun/response.{type Response}

pub fn name() -> String {
  "gluegun"
}

pub fn connect_options() -> ConnectOptions {
  connection.connect_options()
}

pub fn with_transport(
  options: ConnectOptions,
  transport transport: Transport,
) -> ConnectOptions {
  connection.with_transport(options, transport: transport)
}

pub fn with_protocols(
  options: ConnectOptions,
  protocols protocols: List(Protocol),
) -> ConnectOptions {
  connection.with_protocols(options, protocols: protocols)
}

pub fn with_retry(
  options: ConnectOptions,
  retry retry: Timeout,
) -> ConnectOptions {
  connection.with_retry(options, retry: retry)
}

pub fn with_connect_timeout(
  options: ConnectOptions,
  timeout timeout: Timeout,
) -> ConnectOptions {
  connection.with_connect_timeout(options, timeout: timeout)
}

pub fn request_options() -> RequestOptions {
  request.request_options()
}

pub fn method_to_string(method: Method) -> String {
  request.method_to_string(method)
}

pub fn normalize_headers(headers: List(Header)) -> List(Header) {
  request.normalize_headers(headers)
}

pub fn response(
  status status: Int,
  headers headers: List(Header),
  body body: BitArray,
  trailers trailers: List(Header),
) -> Response {
  response.new(status: status, headers: headers, body: body, trailers: trailers)
}
