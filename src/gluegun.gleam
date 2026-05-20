//// Root facade for the Gluegun HTTP client wrapper.
////
//// This module exposes a small common-path facade. Submodules expose grouped
//// APIs for connection, low-level request, response, message, and WebSocket
//// concerns.

import gluegun/client as http_client
import gluegun/connection.{
  type ConnectOptions, type Protocol, type Timeout, type Transport,
}
import gluegun/error
import gluegun/internal.{type Connection}
import gluegun/message
import gluegun/request as low_request
import gluegun/response as http_response
import gluegun/tls
import gluegun/websocket

/// Return the package name.
pub fn name() -> String {
  "gluegun"
}

/// Construct default connection options.
pub fn connection_options() -> ConnectOptions {
  connection.options()
}

/// Open a Gun connection.
pub fn open(
  options: ConnectOptions,
  host host: String,
  port port: Int,
) -> Result(Connection, error.GluegunError) {
  connection.open(options, host: host, port: port)
}

/// Construct default TLS options.
pub fn tls_options() -> tls.TlsOptions {
  tls.options()
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

/// Set TLS options on connection options.
pub fn with_tls_opts(
  options: ConnectOptions,
  tls_opts tls_opts: tls.TlsOptions,
) -> ConnectOptions {
  connection.with_tls_opts(options, tls_opts: tls_opts)
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

/// Construct a collected HTTP request command.
pub fn new_request(
  method: low_request.Method,
  path: String,
) -> http_client.Request {
  http_client.new(method, path)
}

/// Send a collected HTTP request command.
pub fn send(
  request: http_client.Request,
  connection connection: Connection,
) -> Result(http_response.Response, error.GluegunError) {
  http_client.send(request, connection: connection)
}

/// Construct default high-level WebSocket connection options.
pub fn websocket_options() -> websocket.Options {
  websocket.options()
}

/// Open a connection, perform a WebSocket upgrade, and return a reusable socket.
pub fn websocket_connect(
  host host: String,
  port port: Int,
  path path: String,
  options options: websocket.Options,
) -> Result(websocket.Socket, error.GluegunError) {
  websocket.connect(host: host, port: port, path: path, options: options)
}

/// Open a WebSocket, run a callback, then close the WebSocket and connection.
pub fn websocket_with_socket(
  host host: String,
  port port: Int,
  path path: String,
  options options: websocket.Options,
  callback callback: fn(websocket.Socket) -> Result(a, error.GluegunError),
) -> Result(a, error.GluegunError) {
  websocket.with_socket(
    host: host,
    port: port,
    path: path,
    options: options,
    callback: callback,
  )
}

/// Send a text WebSocket frame using a reusable socket.
pub fn websocket_send_text(
  socket: websocket.Socket,
  text: String,
) -> Result(Nil, error.GluegunError) {
  websocket.send_text(socket, text)
}

/// Receive the next application WebSocket frame, handling ping/pong frames.
pub fn websocket_receive_app_frame(
  socket: websocket.Socket,
) -> Result(message.Frame, error.GluegunError) {
  websocket.receive_app_frame(socket)
}

/// Send a close WebSocket frame using a reusable socket.
pub fn websocket_send_close_frame(
  socket: websocket.Socket,
) -> Result(Nil, error.GluegunError) {
  websocket.send_close_frame(socket)
}
