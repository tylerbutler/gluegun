//// WebSocket helpers for Gun connections.
////
//// ## Protocol limitations
////
//// Gun supports WebSocket over HTTP/1.1 only. WebSocket over HTTP/2 (RFC 8441)
//// is **not** supported by Gun. Call `upgrade` with the protocol
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
//// websocket.with_socket(
////   host: "echo.example.com",
////   port: 80,
////   path: "/ws",
////   options: websocket.options(),
////   callback: fn(socket) {
////     use _ <- result.try(websocket.send_frame(socket, message.Text("hello")))
////     case websocket.receive_app_frame(socket) {
////       Ok(message.Text(reply)) -> Ok(reply)
////       Ok(message.Binary(_))
////       | Ok(message.Ping(_))
////       | Ok(message.Pong(_))
////       | Ok(message.Close)
////       | Ok(message.CloseWithReason(_, _)) ->
////         Error(error.InvalidMessage("expected a text frame"))
////       Error(error) -> Error(error)
////     }
////   },
//// )
//// ```

import gleam/erlang/process.{type Pid}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gluegun/connection.{type Connection, type Protocol, type Timeout}
import gluegun/error
import gluegun/message.{type Frame}
import gluegun/request.{type Header, type Stream}

/// A reusable WebSocket handle.
///
/// Wraps the upgraded Gun connection, WebSocket stream, and receive timeout so
/// higher-level helpers can send and receive frames without repeating them.
pub opaque type Socket {
  Socket(
    connection: Connection,
    stream: Stream,
    timeout: Timeout,
    peer_close: PeerClose,
    handshake: Handshake,
  )
}

/// Completed HTTP/1.1 WebSocket handshake, including the response headers and
/// the server's selected subprotocol (if any).
pub opaque type Handshake {
  Handshake(headers: List(Header), selected_subprotocol: Option(String))
}

/// Inspect the completed handshake retained by a socket.
pub fn handshake(socket: Socket) -> Handshake {
  socket.handshake
}

/// Inspect the server-selected subprotocol.
pub fn selected_subprotocol(socket: Socket) -> Option(String) {
  socket.handshake.selected_subprotocol
}

/// Inspect the upgrade response headers, with normalized header names.
pub fn handshake_headers(handshake: Handshake) -> List(Header) {
  handshake.headers
}

/// Inspect the selected subprotocol in a completed handshake.
pub fn handshake_subprotocol(handshake: Handshake) -> Option(String) {
  handshake.selected_subprotocol
}

/// Internal record of a peer close frame received through this socket.
@internal
pub type PeerClose

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
/// `with_compress`, `with_flow`, `with_keepalive`, `with_subprotocols`, and
/// `with_silence_pings`. The fallible `with_flow` builder rejects nonpositive
/// credit.
pub opaque type UpgradeOptions {
  UpgradeOptions(
    closing_timeout: Option(Timeout),
    compress: Option(Bool),
    default_protocol: Option(String),
    flow: Option(Int),
    keepalive: Option(Timeout),
    protocols: List(#(String, String)),
    reply_to: Option(Pid),
    silence_pings: Option(Bool),
    tunnel: Option(Stream),
    handler_options: Option(HandlerOptions),
  )
}

/// The value Gun forwards unchanged to a WebSocket protocol handler module as
/// its `user_opts` upgrade option. Custom handlers are unsupported internal
/// seams; Socket teardown bookkeeping requires Gun's default handler.
@internal
pub type HandlerOptions

/// One Gun WebSocket upgrade option, encoded for the Erlang FFI boundary.
///
/// `upgrade_options_to_ffi` turns `UpgradeOptions` into a list of these
/// values. `src/gluegun_ffi.erl` pattern matches each variant and builds the
/// matching `gun:ws_opts()` map entry.
@internal
pub type UpgradeOption {
  ClosingTimeout(Timeout)
  Compress(Bool)
  DefaultProtocol(String)
  Flow(Int)
  Keepalive(Timeout)
  Protocols(List(#(String, String)))
  ReplyTo(Pid)
  SilencePings(Bool)
  Tunnel(Stream)
  UserOptions(HandlerOptions)
}

/// Construct a reusable WebSocket handle from an upgraded connection and stream.
@internal
pub fn socket(
  connection: Connection,
  stream: Stream,
  timeout: Timeout,
) -> Socket {
  from_upgrade(connection, stream, Handshake([], None), timeout)
}

/// Adopt a completed upgrade. Call immediately after `await_upgrade`, in the
/// process receiving this stream's Gun messages. This process owns receives
/// and close; do not consume frames through another API or receiver, since
/// close tracks delivered frames to restore finite flow credit during teardown.
pub fn from_upgrade(
  connection connection: Connection,
  stream stream: Stream,
  handshake handshake: Handshake,
  timeout timeout: Timeout,
) -> Socket {
  Socket(
    connection: connection,
    stream: stream,
    timeout: timeout,
    peer_close: ffi_peer_close(),
    handshake: handshake,
  )
}

/// Construct default high-level WebSocket connection options.
pub fn options() -> Options {
  Options(
    connect_options: connection.options()
      |> connection.with_protocols([connection.Http1]),
    headers: [],
    upgrade_options: upgrade_options(),
    timeout: connection.default_timeout(),
  )
}

/// Set headers sent with the WebSocket upgrade request.
pub fn with_headers(options: Options, headers headers: List(Header)) -> Options {
  Options(..options, headers: headers)
}

/// Set Gun connection options used when opening the connection.
pub fn with_connect_options(
  options: Options,
  connect_options connect: connection.ConnectOptions,
) -> Options {
  Options(..options, connect_options: connect)
}

/// Set Gun WebSocket upgrade options used for the upgrade request.
pub fn with_upgrade_options(
  options: Options,
  upgrade_options upgrade: UpgradeOptions,
) -> Options {
  Options(..options, upgrade_options: upgrade)
}

/// Set the timeout used when awaiting connection readiness, upgrade, and frames.
pub fn with_timeout(options: Options, timeout timeout: Timeout) -> Options {
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
    handler_options: None,
  )
}

/// Open a Gun connection, perform a WebSocket upgrade, and return a reusable
/// socket.
///
/// The connection is opened with the configured connect options, awaited up
/// to readiness, then upgraded. If any step fails the underlying Gun
/// connection is closed automatically. On success the caller owns the
/// returned `Socket` and must eventually call `close`
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
  use opened_connection <- result.try(connection.open(
    connect_options(options),
    host: host,
    port: port,
  ))

  close_on_error(opened_connection, {
    use protocol <- result.try(connection.await_up(
      opened_connection,
      options.timeout,
    ))
    use stream <- result.try(upgrade(
      opened_connection,
      protocol,
      path,
      options.headers,
      options.upgrade_options,
    ))
    use handshake <- result.try(await_upgrade(
      opened_connection,
      stream,
      options.timeout,
    ))
    Ok(from_upgrade(opened_connection, stream, handshake, options.timeout))
  })
}

/// Effective options: WebSockets cannot negotiate HTTP/2 or resume on retry.
@internal
pub fn connect_options(options: Options) -> connection.ConnectOptions {
  options.connect_options
  |> connection.with_protocols([connection.Http1])
  |> connection.with_retry(connection.default_retry_count())
}

fn close_on_error(
  opened_connection: Connection,
  result: Result(a, error.GluegunError),
) -> Result(a, error.GluegunError) {
  case result {
    Error(error) -> {
      let _ = connection.terminate(opened_connection)
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
/// even when the callback fails. If the callback panics, fails an assertion,
/// or raises an Erlang exception, teardown uses a finite close deadline before
/// re-raising the original exception class, reason, and stack. Cleanup cannot
/// replace it.
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

  let #(callback_result, cleanup_result) =
    ffi_ws_with_cleanup(fn() { callback(socket) }, fn() { close(socket) })
  with_socket_result(callback_result, cleanup_result)
}

/// Combine callback and cleanup results using `with_socket` error precedence.
@internal
pub fn with_socket_result(
  callback_result: Result(a, error.GluegunError),
  cleanup_result: Result(Nil, error.GluegunError),
) -> Result(a, error.GluegunError) {
  use value <- result.try(callback_result)
  use _ <- result.try(cleanup_result)
  Ok(value)
}

/// Set Gun's WebSocket closing timeout.
pub fn with_closing_timeout(
  options: UpgradeOptions,
  timeout timeout: Timeout,
) -> UpgradeOptions {
  UpgradeOptions(..options, closing_timeout: Some(timeout))
}

/// Enable or disable WebSocket compression.
pub fn with_compress(
  options: UpgradeOptions,
  enabled enabled: Bool,
) -> UpgradeOptions {
  UpgradeOptions(..options, compress: Some(enabled))
}

/// Set a positive initial WebSocket flow-control allowance.
pub fn with_flow(
  options: UpgradeOptions,
  initial_flow initial_flow: Int,
) -> Result(UpgradeOptions, error.GluegunError) {
  case initial_flow > 0 {
    True -> Ok(UpgradeOptions(..options, flow: Some(initial_flow)))
    False ->
      Error(error.InvalidOptions("WebSocket initial flow must be positive"))
  }
}

/// Set Gun's WebSocket keepalive timeout.
pub fn with_keepalive(
  options: UpgradeOptions,
  timeout timeout: Timeout,
) -> UpgradeOptions {
  UpgradeOptions(..options, keepalive: Some(timeout))
}

/// Enable or disable silencing automatic ping frames.
pub fn with_silence_pings(
  options: UpgradeOptions,
  enabled enabled: Bool,
) -> UpgradeOptions {
  UpgradeOptions(..options, silence_pings: Some(enabled))
}

/// Set the default WebSocket protocol callback module.
@internal
pub fn with_default_protocol_module(
  options: UpgradeOptions,
  module_name: String,
) -> UpgradeOptions {
  UpgradeOptions(..options, default_protocol: Some(module_name))
}

/// Add a WebSocket subprotocol callback module.
@internal
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

/// Offer subprotocols using Gun's standard WebSocket handler. Every token is
/// validated before sending; order and case are preserved.
pub fn with_subprotocols(
  options: UpgradeOptions,
  protocols protocols: List(String),
) -> UpgradeOptions {
  UpgradeOptions(
    ..options,
    protocols: list.map(protocols, fn(protocol) { #(protocol, "gun_ws_h") }),
  )
}

/// Deliver upgrade and frame messages to this process. That receiver must
/// await the upgrade, adopt it, receive frames, and close its socket.
pub fn with_reply_to(
  options: UpgradeOptions,
  receiver receiver: Pid,
) -> UpgradeOptions {
  with_reply_to_raw(options, receiver)
}

@internal
pub fn with_reply_to_raw(
  options: UpgradeOptions,
  reply_to: Pid,
) -> UpgradeOptions {
  UpgradeOptions(..options, reply_to: Some(reply_to))
}

@internal
pub fn with_tunnel_raw(
  options: UpgradeOptions,
  tunnel: Stream,
) -> UpgradeOptions {
  UpgradeOptions(..options, tunnel: Some(tunnel))
}

@internal
pub fn with_handler_options_raw(
  options: UpgradeOptions,
  handler_options: HandlerOptions,
) -> UpgradeOptions {
  UpgradeOptions(..options, handler_options: Some(handler_options))
}

/// Convert WebSocket upgrade options to the typed shape the Erlang FFI expects.
@internal
pub fn upgrade_options_to_ffi(options: UpgradeOptions) -> List(UpgradeOption) {
  []
  |> prepend_optional(options.closing_timeout, ClosingTimeout)
  |> prepend_optional(options.compress, Compress)
  |> prepend_optional(options.default_protocol, DefaultProtocol)
  |> prepend_optional(options.flow, Flow)
  |> prepend_optional(options.keepalive, Keepalive)
  |> prepend_optional(non_empty(options.protocols), Protocols)
  |> prepend_optional(options.reply_to, ReplyTo)
  |> prepend_optional(options.silence_pings, SilencePings)
  |> prepend_optional(options.tunnel, Tunnel)
  |> prepend_optional(options.handler_options, UserOptions)
}

/// Initiate a WebSocket upgrade with options when the negotiated protocol is known.
///
/// Returns `UnsupportedFeature` for HTTP/2 because Gun does not support
/// WebSocket over HTTP/2. Path, headers, and all subprotocol tokens are
/// validated before calling Gun; invalid input returns `InvalidOptions`.
pub fn upgrade(
  connection connection: Connection,
  protocol protocol: Protocol,
  path path: String,
  headers headers: List(Header),
  options options: UpgradeOptions,
) -> Result(Stream, error.GluegunError) {
  case protocol {
    connection.Http1 ->
      ffi_ws_upgrade(connection, path, headers, upgrade_options_to_ffi(options))
    connection.Http2 ->
      Error(error.UnsupportedFeature("WebSocket upgrade requires HTTP/1.1"))
  }
}

/// Wait for the WebSocket upgrade confirmation (`101 Switching Protocols`).
///
/// Call this after `upgrade`. Informational responses are skipped under one
/// absolute deadline; a zero timeout returns `Timeout` without polling.
/// Successful handshakes retain the response headers and selected subprotocol.
pub fn await_upgrade(
  connection connection: Connection,
  stream stream: Stream,
  timeout timeout: Timeout,
) -> Result(Handshake, error.GluegunError) {
  await_upgrade_until(connection, stream, connection.deadline(timeout))
}

fn await_upgrade_until(
  connection: Connection,
  stream: Stream,
  deadline: Option(Int),
) -> Result(Handshake, error.GluegunError) {
  case connection.expired(deadline) {
    True -> Error(error.Timeout)
    False -> await_upgrade_next(connection, stream, deadline)
  }
}

fn await_upgrade_next(
  connection: Connection,
  stream: Stream,
  deadline: Option(Int),
) -> Result(Handshake, error.GluegunError) {
  use received <- result.try(ffi_ws_await(
    connection,
    stream,
    connection.remaining(deadline),
  ))
  case received {
    message.Inform(_, _) -> await_upgrade_until(connection, stream, deadline)
    message.Response(_, _, _)
    | message.Data(_, _)
    | message.Trailers(_)
    | message.Push(_, _, _, _)
    | message.Upgrade(_, _)
    | message.WebSocket(_) -> await_upgrade_from(Ok(received))
  }
}

/// Send a single WebSocket frame using a reusable socket.
///
/// Supported frame types: `Text`, `Binary`, `Ping`, `Pong`, `Close`,
/// `CloseWithReason`. Invalid control frames return `InvalidMessage` before
/// calling Gun. Ping and Pong payloads can contain at most 125 bytes. Close
/// reasons must be valid UTF-8 and contain at most 123 bytes.
/// Accepted close codes: 1000-1003, 1007-1014, and 3000-4999.
pub fn send_frame(
  socket socket: Socket,
  frame frame: Frame,
) -> Result(Nil, error.GluegunError) {
  ffi_ws_send(socket.connection, socket.stream, [frame])
}

/// Send a text WebSocket frame using a reusable socket.
pub fn send_text(
  socket socket: Socket,
  text text: String,
) -> Result(Nil, error.GluegunError) {
  send_frame(socket, message.Text(text))
}

/// Send a binary WebSocket frame using a reusable socket.
pub fn send_binary(
  socket socket: Socket,
  data data: BitArray,
) -> Result(Nil, error.GluegunError) {
  send_frame(socket, message.Binary(data))
}

/// Send a ping WebSocket frame using a reusable socket.
pub fn ping(
  socket socket: Socket,
  data data: BitArray,
) -> Result(Nil, error.GluegunError) {
  send_frame(socket, message.Ping(data))
}

/// Send a pong WebSocket frame using a reusable socket.
pub fn pong(
  socket socket: Socket,
  data data: BitArray,
) -> Result(Nil, error.GluegunError) {
  send_frame(socket, message.Pong(data))
}

/// Send a close WebSocket frame using a reusable socket.
///
/// This only sends the close frame; it does not close the underlying Gun
/// connection. Follow with `close(socket)` or use
/// `with_socket` for automatic teardown.
pub fn send_close_frame(
  socket socket: Socket,
) -> Result(Nil, error.GluegunError) {
  send_frame(socket, message.Close)
}

/// Send a close frame, await the peer, then release the Gun process.
///
/// Uses one deadline: the socket's finite timeout, or five seconds for
/// `Infinity`. Other frames do not extend it. A missing peer close returns
/// `Timeout`; connection and stream failures return their typed errors.
/// Teardown still terminates the process and flushes its queued Gun messages
/// from this caller after a handshake error. The handshake error takes
/// precedence over a termination error.
///
/// An already-exited connection returns `Ok(Nil)`. Repeated close is safe.
/// Call from the socket's receiver; other receivers and external forwarders
/// need separate mailbox cleanup. Do not reuse the socket after this call.
pub fn close(socket socket: Socket) -> Result(Nil, error.GluegunError) {
  ffi_ws_close(
    socket.connection,
    socket.stream,
    socket.timeout,
    socket.peer_close,
  )
}

/// Send one or more WebSocket frames on the stream.
///
/// Validates the complete list before sending. If a frame is invalid, returns
/// `InvalidMessage` without sending any frame.
///
/// Binary, ping, pong, and close-reason payloads must contain whole bytes.
/// Empty payloads are valid. A non-byte-aligned `BitArray` returns
/// `InvalidMessage` before Gun receives any frame in the list. Payloads are
/// never padded or truncated, and the connection remains usable.
pub fn send_many(
  socket socket: Socket,
  frames frames: List(Frame),
) -> Result(Nil, error.GluegunError) {
  ffi_ws_send(socket.connection, socket.stream, frames)
}

/// Receive the next WebSocket frame using a reusable socket.
///
/// Returns `Ok(frame)` when a WebSocket frame arrives.
/// Returns `Error(InvalidMessage(...))` if a non-WebSocket message arrives
/// (e.g. an HTTP response or upgrade acknowledgement that arrived out of order).
/// Returns `DecodeError` for malformed incoming values, `Timeout` when no
/// frame arrives, and `ConnectionDown` on disconnect (even with Gun retries).
/// Only this socket's stream and connection messages are consumed.
pub fn receive_frame(socket socket: Socket) -> Result(Frame, error.GluegunError) {
  ffi_ws_await(socket.connection, socket.stream, socket.timeout)
  |> receive_from
  |> ffi_record_peer_close(socket.peer_close)
}

/// Receive the next application frame, handling ping/pong control frames.
///
/// Gun automatically answers incoming pings with a matching pong. This helper
/// skips visible ping and pong frames, including empty payloads, without sending
/// another reply. Text, binary, close, and close-with-reason frames are returned
/// to the caller. Use `pong` to send an explicit pong.
///
/// Each call uses one total deadline from the socket's timeout. Skipped
/// control frames do not restart it. `Infinity` permits an unlimited wait;
/// a zero timeout returns `Timeout` without consuming queued frames.
pub fn receive_app_frame(
  socket socket: Socket,
) -> Result(Frame, error.GluegunError) {
  receive_app_frame_until(socket, connection.deadline(socket.timeout))
}

fn receive_app_frame_until(
  socket: Socket,
  deadline: Option(Int),
) -> Result(Frame, error.GluegunError) {
  use _ <- result.try(case connection.expired(deadline) {
    True -> Error(error.Timeout)
    False -> Ok(Nil)
  })
  use frame <- result.try(receive_frame(
    Socket(..socket, timeout: connection.remaining(deadline)),
  ))
  case frame {
    message.Ping(_) | message.Pong(_) ->
      receive_app_frame_until(socket, deadline)
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
) -> Result(Frame, error.GluegunError) {
  case frame_results {
    [] ->
      Error(error.InvalidMessage(
        "websocket.receive_app_frame: expected WebSocket application frame",
      ))
    [frame_result, ..rest] -> {
      use frame <- result.try(frame_result)
      case frame {
        message.Ping(_) | message.Pong(_) -> receive_app_frame_from(rest)
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
/// Production callers should use `receive_frame` instead.
@internal
pub fn receive_from(
  message_result: Result(message.Message, error.GluegunError),
) -> Result(Frame, error.GluegunError) {
  use message <- result.try(message_result)
  case message {
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
) -> Result(Handshake, error.GluegunError) {
  use message <- result.try(message_result)
  case message {
    message.Upgrade(_, headers) -> {
      let selected_result =
        headers
        |> list.find_map(fn(header) {
          case header {
            #("sec-websocket-protocol", value) -> Ok(string.trim(value))
            _ -> Error(Nil)
          }
        })
      let selected = case selected_result {
        Ok(protocol) -> Some(protocol)
        Error(_) -> None
      }
      Ok(Handshake(headers, selected))
    }
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

@external(erlang, "gluegun_ffi", "ws_await")
fn ffi_ws_await(
  connection: Connection,
  stream: Stream,
  timeout: Timeout,
) -> Result(message.Message, error.GluegunError)

@external(erlang, "gluegun_ffi", "ws_upgrade")
fn ffi_ws_upgrade(
  connection: Connection,
  path: String,
  headers: List(Header),
  options: List(UpgradeOption),
) -> Result(Stream, error.GluegunError)

@external(erlang, "gluegun_ffi", "ws_send")
fn ffi_ws_send(
  connection: Connection,
  stream: Stream,
  frames: List(Frame),
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ffi", "ws_peer_close")
fn ffi_peer_close() -> PeerClose

@external(erlang, "gluegun_ffi", "ws_record_peer_close")
fn ffi_record_peer_close(
  frame: Result(Frame, error.GluegunError),
  peer_close: PeerClose,
) -> Result(Frame, error.GluegunError)

@external(erlang, "gluegun_ffi", "ws_close")
fn ffi_ws_close(
  connection: Connection,
  stream: Stream,
  timeout: Timeout,
  peer_close: PeerClose,
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ffi", "ws_with_cleanup")
fn ffi_ws_with_cleanup(
  callback: fn() -> Result(a, error.GluegunError),
  cleanup: fn() -> Result(Nil, error.GluegunError),
) -> #(Result(a, error.GluegunError), Result(Nil, error.GluegunError))

fn prepend_optional(
  options: List(UpgradeOption),
  value: Option(value),
  encode: fn(value) -> UpgradeOption,
) -> List(UpgradeOption) {
  case value {
    Some(value) -> [encode(value), ..options]
    None -> options
  }
}

fn non_empty(values: List(value)) -> Option(List(value)) {
  case values {
    [] -> None
    _ -> Some(values)
  }
}
