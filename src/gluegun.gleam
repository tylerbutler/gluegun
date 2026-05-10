//// Root facade for the gluegun HTTP client wrapper.
////
//// This module re-exports the most commonly used connection, request,
//// response, HTTP helper, and WebSocket operations for callers who prefer one
//// import. Submodules expose the same APIs grouped by concern.

import gluegun/client as http_client
import gluegun/connection.{
  type ConnectOptions, type Protocol, type Timeout, type Transport,
}
import gluegun/error
import gluegun/internal.{type Connection, type Stream}
import gluegun/message
import gluegun/request as low_request
import gluegun/response as http_response
import gluegun/websocket as ws

/// Return the package name.
pub fn name() -> String {
  "gluegun"
}

/// Construct default connection options.
pub fn connect_options() -> ConnectOptions {
  connection.connect_options()
}

/// Set the transport on connection options.
pub fn with_transport(
  options: ConnectOptions,
  transport transport: Transport,
) -> ConnectOptions {
  connection.with_transport(options, transport: transport)
}

/// Set protocol preferences on connection options.
pub fn with_protocols(
  options: ConnectOptions,
  protocols protocols: List(Protocol),
) -> ConnectOptions {
  connection.with_protocols(options, protocols: protocols)
}

/// Set Gun retry timeout on connection options.
pub fn with_retry(
  options: ConnectOptions,
  retry retry: Timeout,
) -> ConnectOptions {
  connection.with_retry(options, retry: retry)
}

/// Set connect timeout on connection options.
pub fn with_connect_timeout(
  options: ConnectOptions,
  timeout timeout: Timeout,
) -> ConnectOptions {
  connection.with_connect_timeout(options, timeout: timeout)
}

/// Construct default request options.
pub fn request_options() -> low_request.RequestOptions {
  low_request.request_options()
}

/// Convert a request method to an HTTP method string.
pub fn method_to_string(method: low_request.Method) -> String {
  low_request.method_to_string(method)
}

/// Normalize header names for Gun.
pub fn normalize_headers(
  headers: List(low_request.Header),
) -> List(low_request.Header) {
  low_request.normalize_headers(headers)
}

/// Construct a collected HTTP response.
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

/// Decode a response body as UTF-8 text.
pub fn body_text(
  response: http_response.Response,
) -> Result(String, error.GluegunError) {
  http_response.body_text(response)
}

/// Send one request and collect the full response.
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

/// Send GET and collect the full response.
pub fn get(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  timeout: Timeout,
) -> Result(http_response.Response, error.GluegunError) {
  http_client.get(connection, path, headers, timeout)
}

/// Send POST and collect the full response.
pub fn post(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  body: BitArray,
  timeout: Timeout,
) -> Result(http_response.Response, error.GluegunError) {
  http_client.post(connection, path, headers, body, timeout)
}

/// Send PUT and collect the full response.
pub fn put(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  body: BitArray,
  timeout: Timeout,
) -> Result(http_response.Response, error.GluegunError) {
  http_client.put(connection, path, headers, body, timeout)
}

/// Send PATCH and collect the full response.
pub fn patch(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  body: BitArray,
  timeout: Timeout,
) -> Result(http_response.Response, error.GluegunError) {
  http_client.patch(connection, path, headers, body, timeout)
}

/// Send DELETE and collect the full response.
pub fn delete(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  timeout: Timeout,
) -> Result(http_response.Response, error.GluegunError) {
  http_client.delete(connection, path, headers, timeout)
}

/// Send HEAD and collect the full response.
pub fn head(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  timeout: Timeout,
) -> Result(http_response.Response, error.GluegunError) {
  http_client.head(connection, path, headers, timeout)
}

/// Send OPTIONS and collect the full response.
pub fn options(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  timeout: Timeout,
) -> Result(http_response.Response, error.GluegunError) {
  http_client.options(connection, path, headers, timeout)
}

/// Initiate a WebSocket upgrade on an HTTP/1.1 connection.
///
/// See `gluegun/websocket` for full documentation and protocol limitations.
pub fn ws_upgrade(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
) -> Result(Stream, error.GluegunError) {
  ws.upgrade(connection, path, headers)
}

/// Initiate a WebSocket upgrade with the negotiated protocol.
///
/// See `gluegun/websocket.upgrade_with_protocol` for details.
pub fn ws_upgrade_with_protocol(
  connection: Connection,
  protocol: Protocol,
  path: String,
  headers: List(low_request.Header),
) -> Result(Stream, error.GluegunError) {
  ws.upgrade_with_protocol(connection, protocol, path, headers)
}

/// Wait for the WebSocket handshake confirmation.
///
/// See `gluegun/websocket.await_upgrade` for details.
pub fn ws_await_upgrade(
  connection: Connection,
  stream: Stream,
  timeout: Timeout,
) -> Result(Nil, error.GluegunError) {
  ws.await_upgrade(connection, stream, timeout)
}

/// Send a single WebSocket frame.
///
/// See `gluegun/websocket.send` for details.
pub fn ws_send(
  connection: Connection,
  stream: Stream,
  frame: message.Frame,
) -> Result(Nil, error.GluegunError) {
  ws.send(connection, stream, frame)
}

/// Send one or more WebSocket frames.
///
/// See `gluegun/websocket.send_many` for details.
pub fn ws_send_many(
  connection: Connection,
  stream: Stream,
  frames: List(message.Frame),
) -> Result(Nil, error.GluegunError) {
  ws.send_many(connection, stream, frames)
}

/// Receive the next WebSocket frame from the stream.
///
/// See `gluegun/websocket.receive` for details.
pub fn ws_receive(
  connection: Connection,
  stream: Stream,
  timeout: Timeout,
) -> Result(message.Frame, error.GluegunError) {
  ws.receive(connection, stream, timeout)
}
