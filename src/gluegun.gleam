//// A small HTTP facade for Gluegun.
////
//// Construct a timeout and connection options, open and await the connection,
//// then build and send a request. Always close or terminate the connection,
//// including after an error. For request customization use `gluegun/client`;
//// for streaming use `gluegun/request` and `gluegun/message`.
//// WebSockets have a complete lifecycle API in `gluegun/websocket`.

import gleam/http.{type Method}
import gluegun/client
import gluegun/connection.{
  type ConnectOptions, type Connection, type Protocol, type Timeout,
}
import gluegun/error
import gluegun/response.{type Response}

/// Construct default connection options, with no automatic retries.
pub fn connection_options() -> ConnectOptions {
  connection.options()
}

/// Construct a non-negative timeout, or return `InvalidOptions`.
pub fn milliseconds(value: Int) -> Result(Timeout, error.GluegunError) {
  connection.milliseconds(value)
}

/// Construct an unlimited timeout.
pub fn infinity() -> Timeout {
  connection.infinity()
}

/// Open a connection. Await readiness before sending a request.
pub fn open(
  options: ConnectOptions,
  host host: String,
  port port: Int,
) -> Result(Connection, error.GluegunError) {
  connection.open(options, host: host, port: port)
}

/// Wait for connection readiness and the negotiated HTTP protocol.
pub fn await_up(
  connection: Connection,
  timeout: Timeout,
) -> Result(Protocol, error.GluegunError) {
  connection.await_up(connection, timeout)
}

/// Construct a request with an empty body and a five-second total budget.
pub fn new_request(method: Method, path: String) -> client.Request {
  client.new(method, path)
}

/// Send a request and collect its complete HTTP response in memory.
pub fn send(
  request: client.Request,
  connection connection: Connection,
) -> Result(Response(BitArray), error.GluegunError) {
  client.send(request, connection: connection)
}

/// Decode the response body as UTF-8.
pub fn body_text(
  response: Response(BitArray),
) -> Result(String, error.GluegunError) {
  response.body_text(response)
}

/// Stop the connection through Gun's supervisor; this does not flush messages.
pub fn close(connection: Connection) -> Result(Nil, error.GluegunError) {
  connection.close(connection)
}

/// Request graceful asynchronous shutdown.
pub fn shutdown(connection: Connection) -> Result(Nil, error.GluegunError) {
  connection.shutdown(connection)
}

/// Force connection exit and flush its queued messages from this receiver.
pub fn terminate(connection: Connection) -> Result(Nil, error.GluegunError) {
  connection.terminate(connection)
}
