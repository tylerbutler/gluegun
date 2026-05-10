//// WebSocket helpers for Gun connections.
////
//// ## Protocol limitations
////
//// Gun supports WebSocket over HTTP/1.1 only. WebSocket over HTTP/2 (RFC 8441)
//// is **not** supported by Gun. Call `upgrade_with_protocol` with the protocol
//// returned by `connection.await_up` to reject HTTP/2 before calling Gun.
////
//// Once an HTTP/1.1 connection is upgraded to WebSocket the underlying TCP
//// connection is exclusively used for WebSocket frames. You cannot send
//// concurrent HTTP requests on that same connection after upgrading.
////
//// ## Typical usage
////
//// ```gleam
//// import gluegun/connection
//// import gluegun/websocket
//// import gluegun/message
////
//// let assert Ok(conn) =
////   connection.options()
////   |> connection.open(host: "echo.example.com", port: 80)
//// let assert Ok(protocol) = connection.await_up(conn, connection.Milliseconds(5000))
////
//// let assert Ok(stream) = websocket.upgrade_with_protocol(conn, protocol, "/ws", [])
//// let assert Ok(Nil) = websocket.await_upgrade(conn, stream, connection.Milliseconds(5000))
////
//// let assert Ok(Nil) = websocket.send(conn, stream, message.Text("hello"))
//// let assert Ok(message.Text(reply)) = websocket.receive(conn, stream, connection.Milliseconds(5000))
//// ```

import gleam/dynamic
import gleam/result
import gluegun/connection.{type Protocol, type Timeout}
import gluegun/error
import gluegun/internal.{type Connection, type Stream}
import gluegun/internal/ffi_result
import gluegun/message.{type Frame}
import gluegun/request.{type Header}

/// Initiate a WebSocket upgrade when the negotiated protocol is known.
///
/// Sends the WebSocket upgrade request to the server and returns the stream
/// reference. Call `await_upgrade` next to confirm the handshake completed.
///
/// Returns `InvalidMessage` for HTTP/2 because Gun does not support WebSocket
/// over HTTP/2. Use this after `connection.await_up` when protocol negotiation
/// may choose HTTP/2.
pub fn upgrade_with_protocol(
  connection: Connection,
  protocol: Protocol,
  path: String,
  headers: List(Header),
) -> Result(Stream, error.GluegunError) {
  case protocol {
    connection.Http1 -> upgrade(connection, path, headers)
    connection.Http2 ->
      Error(error.InvalidMessage(
        "websocket.upgrade: WebSocket over HTTP/2 is not supported by Gun",
      ))
  }
}

/// Initiate a WebSocket upgrade on an assumed HTTP/1.1 connection.
///
/// Prefer `upgrade_with_protocol` after `connection.await_up` when the
/// connection may negotiate HTTP/2. This function keeps the original HTTP/1.1
/// default path for callers that constrain the connection to HTTP/1.1.
pub fn upgrade(
  connection: Connection,
  path: String,
  headers: List(Header),
) -> Result(Stream, error.GluegunError) {
  ffi_ws_upgrade(
    internal.connection_raw(connection),
    path,
    headers,
    dynamic.properties([]),
  )
  |> ffi_result.decode_request_result
}

/// Wait for the WebSocket upgrade confirmation (`101 Switching Protocols`).
///
/// Call this after `upgrade/3`. Returns `Ok(Nil)` when the server confirms
/// the WebSocket handshake. Returns an error on timeout, connection failure,
/// or if a non-upgrade message arrives first.
pub fn await_upgrade(
  connection: Connection,
  stream: Stream,
  timeout: Timeout,
) -> Result(Nil, error.GluegunError) {
  message.await(connection, stream, timeout)
  |> await_upgrade_from
}

/// Send a single WebSocket frame on the stream.
///
/// Supported frame types: `Text`, `Binary`, `Ping`, `Pong`, `Close`,
/// `CloseWithReason`. The frame is forwarded directly to Gun's `ws_send`.
pub fn send(
  connection: Connection,
  stream: Stream,
  frame: Frame,
) -> Result(Nil, error.GluegunError) {
  send_many(connection, stream, [frame])
}

/// Send one or more WebSocket frames on the stream.
///
/// Gun accepts either a single frame or a list of frames. `send` delegates to
/// this function with a one-element list.
pub fn send_many(
  connection: Connection,
  stream: Stream,
  frames: List(Frame),
) -> Result(Nil, error.GluegunError) {
  ffi_ws_send(
    internal.connection_raw(connection),
    internal.stream_raw(stream),
    frames,
  )
  |> ffi_result.decode_nil_result
}

/// Receive the next WebSocket frame from the stream.
///
/// Returns `Ok(frame)` when a WebSocket frame arrives.
/// Returns `Error(InvalidMessage(...))` if a non-WebSocket message arrives
/// (e.g. an HTTP response or upgrade acknowledgement that arrived out of order).
/// Returns `Error(Timeout)` or stream errors on failures.
///
/// If the upgrade acknowledgement has not yet been received, call
/// `await_upgrade/3` before calling `receive`.
pub fn receive(
  connection: Connection,
  stream: Stream,
  timeout: Timeout,
) -> Result(Frame, error.GluegunError) {
  message.await(connection, stream, timeout)
  |> receive_from
}

/// Route a pre-resolved message result to a WebSocket frame.
///
/// This is an internal helper exposed for deterministic unit testing.
/// Production callers should use `receive/3` instead.
@internal
pub fn receive_from(
  message_result: Result(message.Message, error.GluegunError),
) -> Result(Frame, error.GluegunError) {
  use msg <- result.try(message_result)
  case msg {
    message.WebSocket(frame) -> Ok(frame)
    message.Upgrade(_, _) ->
      Error(error.InvalidMessage(
        "websocket.receive: expected WebSocket frame, got Upgrade message; call await_upgrade first",
      ))
    _ ->
      Error(error.InvalidMessage(
        "websocket.receive: expected WebSocket frame, got HTTP message",
      ))
  }
}

/// Route a pre-resolved message result to an upgrade confirmation.
///
/// This is an internal helper exposed for deterministic unit testing.
/// Production callers should use `await_upgrade/3` instead.
@internal
pub fn await_upgrade_from(
  message_result: Result(message.Message, error.GluegunError),
) -> Result(Nil, error.GluegunError) {
  use msg <- result.try(message_result)
  case msg {
    message.Upgrade(_, _) -> Ok(Nil)
    _ ->
      Error(error.InvalidMessage(
        "websocket.await_upgrade: expected Upgrade message",
      ))
  }
}

@external(erlang, "gluegun_ffi", "ws_upgrade")
fn ffi_ws_upgrade(
  connection: dynamic.Dynamic,
  path: String,
  headers: List(Header),
  opts: dynamic.Dynamic,
) -> Result(dynamic.Dynamic, dynamic.Dynamic)

@external(erlang, "gluegun_ffi", "ws_send")
fn ffi_ws_send(
  connection: dynamic.Dynamic,
  stream: dynamic.Dynamic,
  frames: List(Frame),
) -> Result(dynamic.Dynamic, dynamic.Dynamic)
