//// Minimal common-path facade for the Gluegun HTTP client wrapper.
////
//// For full functionality import the submodules (`gluegun/connection`,
//// `gluegun/request`, `gluegun/client`, `gluegun/websocket`,
//// `gluegun/message`, `gluegun/response`, `gluegun/error`).

import gluegun/client as http_client
import gluegun/connection.{
  type ConnectOptions, type Connection, type Protocol, type Timeout,
}
import gluegun/error
import gluegun/request
import gluegun/response as http_response
import gluegun/websocket

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

/// Wait until a Gun connection is up.
pub fn await_up(
  conn: Connection,
  timeout: Timeout,
) -> Result(Protocol, error.GluegunError) {
  connection.await_up(conn, timeout)
}

/// Construct a collected HTTP request command.
pub fn new_request(method: request.Method, path: String) -> http_client.Request {
  http_client.new(method, path)
}

/// Send a collected HTTP request command.
pub fn send(
  request: http_client.Request,
  connection connection: Connection,
) -> Result(http_response.Response, error.GluegunError) {
  http_client.send(request, connection: connection)
}

/// Decode a response body as UTF-8 text.
pub fn body_text(
  response: http_response.Response,
) -> Result(String, error.GluegunError) {
  http_response.body_text(response)
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
