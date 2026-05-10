/// Main module for gluegun.
///
/// gluegun is a Gleam wrapper for the Erlang Gun HTTP client.
import gluegun/client as http_client
import gluegun/connection.{
  type ConnectOptions, type Protocol, type Timeout, type Transport,
}
import gluegun/error
import gluegun/internal.{type Connection}
import gluegun/request as low_request
import gluegun/response as http_response

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

pub fn request_options() -> low_request.RequestOptions {
  low_request.request_options()
}

pub fn method_to_string(method: low_request.Method) -> String {
  low_request.method_to_string(method)
}

pub fn normalize_headers(
  headers: List(low_request.Header),
) -> List(low_request.Header) {
  low_request.normalize_headers(headers)
}

pub fn response(
  status status: Int,
  headers headers: List(low_request.Header),
  body body: BitArray,
  trailers trailers: List(low_request.Header),
) -> http_response.Response {
  http_response.new(
    status: status,
    headers: headers,
    body: body,
    trailers: trailers,
  )
}

pub fn body_text(
  response: http_response.Response,
) -> Result(String, error.GluegunError) {
  http_response.body_text(response)
}

pub fn request(
  connection: Connection,
  method: low_request.Method,
  path: String,
  headers: List(low_request.Header),
  body: BitArray,
  options: low_request.RequestOptions,
  timeout: Timeout,
) -> Result(http_response.Response, error.GluegunError) {
  http_client.request(connection, method, path, headers, body, options, timeout)
}

pub fn get(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  timeout: Timeout,
) -> Result(http_response.Response, error.GluegunError) {
  http_client.get(connection, path, headers, timeout)
}

pub fn post(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  body: BitArray,
  timeout: Timeout,
) -> Result(http_response.Response, error.GluegunError) {
  http_client.post(connection, path, headers, body, timeout)
}

pub fn put(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  body: BitArray,
  timeout: Timeout,
) -> Result(http_response.Response, error.GluegunError) {
  http_client.put(connection, path, headers, body, timeout)
}

pub fn patch(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  body: BitArray,
  timeout: Timeout,
) -> Result(http_response.Response, error.GluegunError) {
  http_client.patch(connection, path, headers, body, timeout)
}

pub fn delete(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  timeout: Timeout,
) -> Result(http_response.Response, error.GluegunError) {
  http_client.delete(connection, path, headers, timeout)
}

pub fn head(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  timeout: Timeout,
) -> Result(http_response.Response, error.GluegunError) {
  http_client.head(connection, path, headers, timeout)
}

pub fn options(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  timeout: Timeout,
) -> Result(http_response.Response, error.GluegunError) {
  http_client.options(connection, path, headers, timeout)
}
