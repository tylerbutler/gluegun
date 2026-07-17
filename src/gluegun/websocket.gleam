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
//// import gleam/result
//// import gluegun/connection
//// import gluegun/error
//// import gluegun/message
//// import gluegun/websocket
////
//// use conn <- result.try(
////   connection.options()
////   |> connection.open(host: "echo.example.com", port: 80),
//// )
////
//// use protocol <- result.try(connection.await_up(conn, connection.Milliseconds(5000)))
////
//// use stream <- result.try(websocket.upgrade_with_protocol(conn, protocol, "/ws", []))
//// use _ <- result.try(websocket.await_upgrade(conn, stream, connection.Milliseconds(5000)))
////
//// use _ <- result.try(websocket.send(conn, stream, message.Text("hello")))
////
//// case websocket.receive(conn, stream, connection.Milliseconds(5000)) {
////   Ok(message.Text(reply)) -> Ok(reply)
////   Ok(_) -> Error(error.InvalidMessage("expected a text frame"))
////   Error(err) -> Error(err)
//// }
//// ```

import gleam/dynamic
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gluegun/connection.{type Connection, type Protocol, type Timeout}
import gluegun/error
import gluegun/internal
import gluegun/internal/ffi_result
import gluegun/message.{type Frame}
import gluegun/request.{type Header, type Stream}

/// A reusable WebSocket handle.
///
/// Wraps the upgraded Gun connection, WebSocket stream, and receive timeout so
/// higher-level helpers can send and receive frames without repeating them.
pub opaque type Socket {
  Socket(connection: Connection, stream: Stream, timeout: Timeout)
}

/// High-level options for opening and upgrading a WebSocket connection.
///
/// Build with `options()` then chain `with_headers`, `with_connect_options`,
/// `with_upgrade_options`, and `with_timeout`. Defaults to HTTP/1.1; Gun's
/// HTTP/2 protocol is rejected before upgrade.
pub opaque type Options {
  Options(
    connect_options: connection.ConnectOptions,
    headers: List(Header),
    upgrade_options: UpgradeOptions,
    timeout: Timeout,
  )
}

/// Typed options for Gun WebSocket upgrades.
///
/// Build with `upgrade_options()` then chain `with_closing_timeout`,
/// `with_compress`, `with_default_protocol`, `with_flow`, `with_keepalive`,
/// `with_protocols`, `with_silence_pings`, etc.
pub opaque type UpgradeOptions {
  UpgradeOptions(
    closing_timeout: Option(Timeout),
    compress: Option(Bool),
    default_protocol: Option(String),
    flow: Option(Int),
    keepalive: Option(Timeout),
    protocols: List(#(String, String)),
    reply_to: Option(dynamic.Dynamic),
    silence_pings: Option(Bool),
    tunnel: Option(dynamic.Dynamic),
    user_opts: Option(dynamic.Dynamic),
  )
}

/// Construct a reusable WebSocket handle from an upgraded connection and stream.
@internal
pub fn socket(
  connection: Connection,
  stream: Stream,
  timeout: Timeout,
) -> Socket {
  Socket(connection: connection, stream: stream, timeout: timeout)
}

/// Construct default high-level WebSocket connection options.
pub fn options() -> Options {
  Options(
    connect_options: connection.options()
      |> connection.with_protocols([connection.Http1]),
    headers: [],
    upgrade_options: upgrade_options(),
    timeout: connection.Milliseconds(5000),
  )
}

/// Set headers sent with the WebSocket upgrade request.
pub fn with_headers(options: Options, headers: List(Header)) -> Options {
  Options(..options, headers: headers)
}

/// Set Gun connection options used when opening the connection.
pub fn with_connect_options(
  options: Options,
  connect: connection.ConnectOptions,
) -> Options {
  Options(..options, connect_options: connect)
}

/// Set Gun WebSocket upgrade options used for the upgrade request.
pub fn with_upgrade_options(
  options: Options,
  upgrade: UpgradeOptions,
) -> Options {
  Options(..options, upgrade_options: upgrade)
}

/// Set the timeout used when awaiting connection readiness, upgrade, and frames.
pub fn with_timeout(options: Options, timeout: Timeout) -> Options {
  Options(..options, timeout: timeout)
}

/// Inspect configured upgrade headers. Intended for deterministic tests.
@internal
pub fn options_headers(options: Options) -> List(Header) {
  options.headers
}

/// Inspect configured connection options. Intended for deterministic tests.
@internal
pub fn options_connect_options(options: Options) -> connection.ConnectOptions {
  options.connect_options
}

/// Inspect configured upgrade options. Intended for deterministic tests.
@internal
pub fn options_upgrade_options(options: Options) -> UpgradeOptions {
  options.upgrade_options
}

/// Inspect configured timeout. Intended for deterministic tests.
@internal
pub fn options_timeout(options: Options) -> Timeout {
  options.timeout
}

/// Construct default WebSocket upgrade options.
pub fn upgrade_options() -> UpgradeOptions {
  UpgradeOptions(
    closing_timeout: None,
    compress: None,
    default_protocol: None,
    flow: None,
    keepalive: None,
    protocols: [],
    reply_to: None,
    silence_pings: None,
    tunnel: None,
    user_opts: None,
  )
}

/// Open a Gun connection, perform a WebSocket upgrade, and return a reusable
/// socket.
///
/// The connection is opened with the configured connect options, awaited up
/// to readiness, then upgraded. If any step fails the underlying Gun
/// connection is closed automatically. On success the caller owns the
/// returned `Socket` and must eventually `send_close_frame` + `connection.close`
/// (or use `with_socket` for scoped cleanup).
///
/// Defaults to HTTP/1.1; HTTP/2 is rejected with `UnsupportedFeature`
/// because Gun does not support WebSocket over HTTP/2.
pub fn connect(
  host host: String,
  port port: Int,
  path path: String,
  options options: Options,
) -> Result(Socket, error.GluegunError) {
  use conn <- result.try(connection.open(
    options.connect_options,
    host: host,
    port: port,
  ))

  close_on_error(conn, {
    use protocol <- result.try(connection.await_up(conn, options.timeout))
    use stream <- result.try(upgrade_with_protocol_and_options(
      conn,
      protocol,
      path,
      options.headers,
      options.upgrade_options,
    ))
    use _ <- result.try(await_upgrade(conn, stream, options.timeout))
    Ok(socket(conn, stream, options.timeout))
  })
}

fn close_on_error(
  conn: Connection,
  result: Result(a, error.GluegunError),
) -> Result(a, error.GluegunError) {
  case result {
    Error(error) -> {
      let _ = connection.close(conn)
      Error(error)
    }
    Ok(value) -> Ok(value)
  }
}

/// Open a WebSocket, run a callback, then send the close frame and close
/// the underlying connection.
///
/// Scoped lifecycle helper. Use this when the WebSocket session is
/// self-contained. The callback receives a reusable `Socket`. Errors from
/// the callback take precedence over cleanup errors; cleanup is attempted
/// even when the callback fails.
pub fn with_socket(
  host host: String,
  port port: Int,
  path path: String,
  options options: Options,
  callback callback: fn(Socket) -> Result(a, error.GluegunError),
) -> Result(a, error.GluegunError) {
  use socket <- result.try(connect(
    host: host,
    port: port,
    path: path,
    options: options,
  ))

  let callback_result = callback(socket)
  let close_frame_result = send_close_frame(socket)
  let close_connection_result = connection.close(socket.connection)

  with_socket_result(
    callback_result,
    close_frame_result,
    close_connection_result,
  )
}

/// Combine callback and cleanup results using `with_socket` error precedence.
@internal
pub fn with_socket_result(
  callback_result: Result(a, error.GluegunError),
  close_frame_result: Result(Nil, error.GluegunError),
  close_connection_result: Result(Nil, error.GluegunError),
) -> Result(a, error.GluegunError) {
  use value <- result.try(callback_result)
  use _ <- result.try(close_frame_result)
  use _ <- result.try(close_connection_result)
  Ok(value)
}

/// Set Gun's WebSocket closing timeout.
pub fn with_closing_timeout(
  options: UpgradeOptions,
  timeout: Timeout,
) -> UpgradeOptions {
  UpgradeOptions(..options, closing_timeout: Some(timeout))
}

/// Enable or disable WebSocket compression.
pub fn with_compress(options: UpgradeOptions, enabled: Bool) -> UpgradeOptions {
  UpgradeOptions(..options, compress: Some(enabled))
}

/// Set the initial WebSocket flow-control allowance.
pub fn with_flow(options: UpgradeOptions, initial_flow: Int) -> UpgradeOptions {
  UpgradeOptions(..options, flow: Some(initial_flow))
}

/// Set Gun's WebSocket keepalive timeout.
pub fn with_keepalive(
  options: UpgradeOptions,
  timeout: Timeout,
) -> UpgradeOptions {
  UpgradeOptions(..options, keepalive: Some(timeout))
}

/// Enable or disable silencing automatic ping frames.
pub fn with_silence_pings(
  options: UpgradeOptions,
  enabled: Bool,
) -> UpgradeOptions {
  UpgradeOptions(..options, silence_pings: Some(enabled))
}

/// Set the default WebSocket protocol callback module.
pub fn with_default_protocol_module(
  options: UpgradeOptions,
  module_name: String,
) -> UpgradeOptions {
  UpgradeOptions(..options, default_protocol: Some(module_name))
}

/// Add a WebSocket subprotocol callback module.
pub fn with_protocol_module(
  options: UpgradeOptions,
  protocol: String,
  module_name: String,
) -> UpgradeOptions {
  UpgradeOptions(
    ..options,
    protocols: list.append(options.protocols, [#(protocol, module_name)]),
  )
}

@internal
pub fn with_reply_to_raw(
  options: UpgradeOptions,
  reply_to: dynamic.Dynamic,
) -> UpgradeOptions {
  UpgradeOptions(..options, reply_to: Some(reply_to))
}

@internal
pub fn with_tunnel_raw(
  options: UpgradeOptions,
  tunnel: dynamic.Dynamic,
) -> UpgradeOptions {
  UpgradeOptions(..options, tunnel: Some(tunnel))
}

@internal
pub fn with_user_opts_raw(
  options: UpgradeOptions,
  user_opts: dynamic.Dynamic,
) -> UpgradeOptions {
  UpgradeOptions(..options, user_opts: Some(user_opts))
}

/// Convert WebSocket upgrade options to the Erlang FFI map shape.
@internal
pub fn upgrade_options_to_ffi(options: UpgradeOptions) -> dynamic.Dynamic {
  []
  |> prepend_optional(
    "closing_timeout",
    options.closing_timeout,
    connection.timeout_to_ffi,
  )
  |> prepend_optional("compress", options.compress, dynamic.bool)
  |> prepend_optional(
    "default_protocol",
    options.default_protocol,
    dynamic.string,
  )
  |> prepend_optional("flow", options.flow, dynamic.int)
  |> prepend_optional("keepalive", options.keepalive, connection.timeout_to_ffi)
  |> prepend_optional(
    "protocols",
    non_empty(options.protocols),
    encode_protocols,
  )
  |> prepend_optional("reply_to", options.reply_to, fn(value) { value })
  |> prepend_optional("silence_pings", options.silence_pings, dynamic.bool)
  |> prepend_optional("tunnel", options.tunnel, fn(value) { value })
  |> prepend_optional("user_opts", options.user_opts, fn(value) { value })
  |> dynamic.properties
}

/// Initiate a WebSocket upgrade when the negotiated protocol is known.
///
/// Sends the WebSocket upgrade request to the server and returns the stream
/// reference. Call `await_upgrade` next to confirm the handshake completed.
///
/// Returns `UnsupportedFeature` for HTTP/2 because Gun does not support
/// WebSocket over HTTP/2. Use this after `connection.await_up` when protocol
/// negotiation may choose HTTP/2.
pub fn upgrade_with_protocol(
  connection: Connection,
  protocol: Protocol,
  path: String,
  headers: List(Header),
) -> Result(Stream, error.GluegunError) {
  upgrade_with_protocol_and_options(
    connection,
    protocol,
    path,
    headers,
    upgrade_options(),
  )
}

/// Initiate a WebSocket upgrade with options when the negotiated protocol is known.
///
/// Returns `UnsupportedFeature` for HTTP/2 because Gun does not support
/// WebSocket over HTTP/2.
pub fn upgrade_with_protocol_and_options(
  connection: Connection,
  protocol: Protocol,
  path: String,
  headers: List(Header),
  options: UpgradeOptions,
) -> Result(Stream, error.GluegunError) {
  case protocol {
    connection.Http1 -> upgrade_with_options(connection, path, headers, options)
    connection.Http2 ->
      Error(error.UnsupportedFeature("WebSocket upgrade requires HTTP/1.1"))
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
  upgrade_with_options(connection, path, headers, upgrade_options())
}

/// Initiate a WebSocket upgrade on an assumed HTTP/1.1 connection with options.
pub fn upgrade_with_options(
  connection: Connection,
  path: String,
  headers: List(Header),
  options: UpgradeOptions,
) -> Result(Stream, error.GluegunError) {
  ffi_ws_upgrade(
    internal.connection_raw(connection),
    path,
    headers,
    upgrade_options_to_ffi(options),
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

/// Send a single WebSocket frame using a reusable socket.
pub fn send_frame(
  socket: Socket,
  frame: Frame,
) -> Result(Nil, error.GluegunError) {
  send(socket.connection, socket.stream, frame)
}

/// Send a text WebSocket frame using a reusable socket.
pub fn send_text(
  socket: Socket,
  text: String,
) -> Result(Nil, error.GluegunError) {
  send_frame(socket, message.Text(text))
}

/// Send a binary WebSocket frame using a reusable socket.
pub fn send_binary(
  socket: Socket,
  data: BitArray,
) -> Result(Nil, error.GluegunError) {
  send_frame(socket, message.Binary(data))
}

/// Send a ping WebSocket frame using a reusable socket.
pub fn ping(socket: Socket, data: BitArray) -> Result(Nil, error.GluegunError) {
  send_frame(socket, message.Ping(data))
}

/// Send a pong WebSocket frame using a reusable socket.
pub fn pong(socket: Socket, data: BitArray) -> Result(Nil, error.GluegunError) {
  send_frame(socket, message.Pong(data))
}

/// Send a close WebSocket frame using a reusable socket.
///
/// This only sends the close frame; it does not close the underlying Gun
/// connection. Follow with `connection.close(socket.connection)` or use
/// `with_socket` for automatic teardown.
pub fn send_close_frame(socket: Socket) -> Result(Nil, error.GluegunError) {
  send_frame(socket, message.Close)
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

/// Receive the next WebSocket frame using a reusable socket.
pub fn receive_frame(socket: Socket) -> Result(Frame, error.GluegunError) {
  receive(socket.connection, socket.stream, socket.timeout)
}

/// Receive the next application frame, handling ping/pong control frames.
///
/// Incoming pings are answered with a pong carrying the same payload. Incoming
/// pongs are skipped. Text, binary, close, and close-with-reason frames are
/// returned to the caller.
pub fn receive_app_frame(socket: Socket) -> Result(Frame, error.GluegunError) {
  use frame <- result.try(receive_frame(socket))
  case frame {
    message.Ping(payload) -> {
      use _ <- result.try(pong(socket, payload))
      receive_app_frame(socket)
    }
    message.Pong(_) -> receive_app_frame(socket)
    message.Text(_)
    | message.Binary(_)
    | message.Close
    | message.CloseWithReason(_, _) -> Ok(frame)
  }
}

/// Route pre-resolved frame results through application-frame handling.
///
/// This is an internal helper exposed for deterministic unit testing.
/// Production callers should use `receive_app_frame/1` instead.
@internal
pub fn receive_app_frame_from(
  frame_results: List(Result(Frame, error.GluegunError)),
  send_pong: fn(BitArray) -> Result(Nil, error.GluegunError),
) -> Result(Frame, error.GluegunError) {
  case frame_results {
    [] ->
      Error(error.InvalidMessage(
        "websocket.receive_app_frame: expected WebSocket application frame",
      ))
    [frame_result, ..rest] -> {
      use frame <- result.try(frame_result)
      case frame {
        message.Ping(payload) -> {
          use _ <- result.try(send_pong(payload))
          receive_app_frame_from(rest, send_pong)
        }
        message.Pong(_) -> receive_app_frame_from(rest, send_pong)
        message.Text(_)
        | message.Binary(_)
        | message.Close
        | message.CloseWithReason(_, _) -> Ok(frame)
      }
    }
  }
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
    message.Inform(_, _)
    | message.Response(_, _, _)
    | message.Data(_, _)
    | message.Trailers(_)
    | message.Push(_, _, _, _) ->
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
    message.Inform(_, _)
    | message.Response(_, _, _)
    | message.Data(_, _)
    | message.Trailers(_)
    | message.Push(_, _, _, _)
    | message.WebSocket(_) ->
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

fn prepend_optional(
  fields: List(#(dynamic.Dynamic, dynamic.Dynamic)),
  key: String,
  value: Option(a),
  encode: fn(a) -> dynamic.Dynamic,
) -> List(#(dynamic.Dynamic, dynamic.Dynamic)) {
  case value {
    Some(value) -> [#(dynamic.string(key), encode(value)), ..fields]
    None -> fields
  }
}

fn non_empty(values: List(a)) -> Option(List(a)) {
  case values {
    [] -> None
    _ -> Some(values)
  }
}

fn encode_protocols(protocols: List(#(String, String))) -> dynamic.Dynamic {
  dynamic.list(
    list.map(protocols, fn(protocol) {
      dynamic.array([
        dynamic.string(protocol.0),
        dynamic.string(protocol.1),
      ])
    }),
  )
}
