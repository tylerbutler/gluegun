---
title: gluegun/websocket
description: WebSocket helpers for Gun connections.
---

WebSocket helpers for Gun connections.

 ## Protocol limitations

 Gun supports WebSocket over HTTP/1.1 only. WebSocket over HTTP/2 (RFC 8441)
 is **not** supported by Gun. Call `upgrade` with the protocol
 returned by `connection.await_up` to reject HTTP/2 before calling Gun.

 Once an HTTP/1.1 connection is upgraded to WebSocket the underlying TCP
 connection is exclusively used for WebSocket frames. You cannot send
 concurrent HTTP requests on that same connection after upgrading.

 ## Typical usage

 ```gleam
 import gleam/result
 import gluegun/connection
 import gluegun/error
 import gluegun/message
 import gluegun/websocket

 websocket.with_socket(
   host: "echo.example.com",
   port: 80,
   path: "/ws",
   options: websocket.options(),
   callback: fn(socket) {
     use _ <- result.try(websocket.send_frame(socket, message.Text("hello")))
     case websocket.receive_app_frame(socket) {
       Ok(message.Text(reply)) -> Ok(reply)
       Ok(message.Binary(_))
       | Ok(message.Ping(_))
       | Ok(message.Pong(_))
       | Ok(message.Close)
       | Ok(message.CloseWithReason(_, _)) ->
         Error(error.InvalidMessage("expected a text frame"))
       Error(error) -> Error(error)
     }
   },
 )
 ```

## Types

### `Handshake`

Completed HTTP/1.1 WebSocket handshake, including the response headers and
 the server's selected subprotocol (if any).

```gleam
pub type Handshake
```

### `Options`

High-level options for opening and upgrading a WebSocket connection.

 Build with `options()` then chain `with_headers`, `with_connect_options`,
 `with_upgrade_options`, and `with_timeout`. Defaults to HTTP/1.1; Gun's
 HTTP/2 protocol is rejected before upgrade.

```gleam
pub type Options
```

### `Socket`

A reusable WebSocket handle.

 Wraps the upgraded Gun connection, WebSocket stream, and receive timeout so
 higher-level helpers can send and receive frames without repeating them.

```gleam
pub type Socket
```

### `UpgradeOptions`

Typed options for Gun WebSocket upgrades.

 Build with `upgrade_options()` then chain `with_closing_timeout`,
 `with_compress`, `with_flow`, `with_keepalive`, `with_subprotocols`, and
 `with_silence_pings`. The fallible `with_flow` builder rejects nonpositive
 credit.

```gleam
pub type UpgradeOptions
```

## Functions

### `await_upgrade`

Wait for the WebSocket upgrade confirmation (`101 Switching Protocols`).

 Call this after `upgrade`. Informational responses are skipped under one
 absolute deadline; a zero timeout returns `Timeout` without polling.
 Successful handshakes retain the response headers and selected subprotocol.

```gleam
pub fn await_upgrade(
  connection: internal.Connection,
  stream: internal.Stream,
  timeout: connection.Timeout
) -> Result(Handshake, error.GluegunError)
```

### `close`

Send a close frame, await the peer, then release the Gun process.

 Uses one deadline: the socket's finite timeout, or five seconds for
 `Infinity`. Other frames do not extend it. A missing peer close returns
 `Timeout`; connection and stream failures return their typed errors.
 Teardown still terminates the process and flushes its queued Gun messages
 from this caller after a handshake error. The handshake error takes
 precedence over a termination error.

 An already-exited connection returns `Ok(Nil)`. Repeated close is safe.
 Call from the socket's receiver; other receivers and external forwarders
 need separate mailbox cleanup. Do not reuse the socket after this call.

```gleam
pub fn close(socket: Socket) -> Result(Nil, error.GluegunError)
```

### `connect`

Open a Gun connection, perform a WebSocket upgrade, and return a reusable
 socket.

 The connection is opened with the configured connect options, awaited up
 to readiness, then upgraded. If any step fails the underlying Gun
 connection is closed automatically. On success the caller owns the
 returned `Socket` and must eventually call `close`
 (or use `with_socket` for scoped cleanup).

 Defaults to HTTP/1.1; HTTP/2 is rejected with `UnsupportedFeature`
 because Gun does not support WebSocket over HTTP/2.

```gleam
pub fn connect(
  host: String,
  port: Int,
  path: String,
  options: Options
) -> Result(Socket, error.GluegunError)
```

### `from_upgrade`

Adopt a completed upgrade. Call immediately after `await_upgrade`, in the
 process receiving this stream's Gun messages. This process owns receives
 and close; do not consume frames through another API or receiver, since
 close tracks delivered frames to restore finite flow credit during teardown.

```gleam
pub fn from_upgrade(
  connection: internal.Connection,
  stream: internal.Stream,
  handshake: Handshake,
  timeout: connection.Timeout
) -> Socket
```

### `handshake`

Inspect the completed handshake retained by a socket.

```gleam
pub fn handshake(Socket) -> Handshake
```

### `handshake_headers`

Inspect the upgrade response headers, with normalized header names.

```gleam
pub fn handshake_headers(Handshake) -> List(#(String, String))
```

### `handshake_subprotocol`

Inspect the selected subprotocol in a completed handshake.

```gleam
pub fn handshake_subprotocol(Handshake) -> option.Option(String)
```

### `options`

Construct default high-level WebSocket connection options.

```gleam
pub fn options() -> Options
```

### `ping`

Send a ping WebSocket frame using a reusable socket.

```gleam
pub fn ping(
  socket: Socket,
  data: BitArray
) -> Result(Nil, error.GluegunError)
```

### `pong`

Send a pong WebSocket frame using a reusable socket.

```gleam
pub fn pong(
  socket: Socket,
  data: BitArray
) -> Result(Nil, error.GluegunError)
```

### `receive_app_frame`

Receive the next application frame, handling ping/pong control frames.

 Gun automatically answers incoming pings with a matching pong. This helper
 skips visible ping and pong frames, including empty payloads, without sending
 another reply. Text, binary, close, and close-with-reason frames are returned
 to the caller. Use `pong` to send an explicit pong.

 Each call uses one total deadline from the socket's timeout. Skipped
 control frames do not restart it. `Infinity` permits an unlimited wait;
 a zero timeout returns `Timeout` without consuming queued frames.

```gleam
pub fn receive_app_frame(socket: Socket) -> Result(message.Frame, error.GluegunError)
```

### `receive_frame`

Receive the next WebSocket frame using a reusable socket.

 Returns `Ok(frame)` when a WebSocket frame arrives.
 Returns `Error(InvalidMessage(...))` if a non-WebSocket message arrives
 (e.g. an HTTP response or upgrade acknowledgement that arrived out of order).
 Returns `DecodeError` for malformed incoming values, `Timeout` when no
 frame arrives, and `ConnectionDown` on disconnect (even with Gun retries).
 Only this socket's stream and connection messages are consumed.

```gleam
pub fn receive_frame(socket: Socket) -> Result(message.Frame, error.GluegunError)
```

### `selected_subprotocol`

Inspect the server-selected subprotocol.

```gleam
pub fn selected_subprotocol(Socket) -> option.Option(String)
```

### `send_binary`

Send a binary WebSocket frame using a reusable socket.

```gleam
pub fn send_binary(
  socket: Socket,
  data: BitArray
) -> Result(Nil, error.GluegunError)
```

### `send_close_frame`

Send a close WebSocket frame using a reusable socket.

 This only sends the close frame; it does not close the underlying Gun
 connection. Follow with `close(socket)` or use
 `with_socket` for automatic teardown.

```gleam
pub fn send_close_frame(socket: Socket) -> Result(Nil, error.GluegunError)
```

### `send_frame`

Send a single WebSocket frame using a reusable socket.

 Supported frame types: `Text`, `Binary`, `Ping`, `Pong`, `Close`,
 `CloseWithReason`. Invalid control frames return `InvalidMessage` before
 calling Gun. Ping and Pong payloads can contain at most 125 bytes. Close
 reasons must be valid UTF-8 and contain at most 123 bytes.
 Accepted close codes: 1000-1003, 1007-1014, and 3000-4999.

```gleam
pub fn send_frame(
  socket: Socket,
  frame: message.Frame
) -> Result(Nil, error.GluegunError)
```

### `send_many`

Send one or more WebSocket frames on the stream.

 Validates the complete list before sending. If a frame is invalid, returns
 `InvalidMessage` without sending any frame.

 Binary, ping, pong, and close-reason payloads must contain whole bytes.
 Empty payloads are valid. A non-byte-aligned `BitArray` returns
 `InvalidMessage` before Gun receives any frame in the list. Payloads are
 never padded or truncated, and the connection remains usable.

```gleam
pub fn send_many(
  socket: Socket,
  frames: List(message.Frame)
) -> Result(Nil, error.GluegunError)
```

### `send_text`

Send a text WebSocket frame using a reusable socket.

```gleam
pub fn send_text(
  socket: Socket,
  text: String
) -> Result(Nil, error.GluegunError)
```

### `upgrade`

Initiate a WebSocket upgrade with options when the negotiated protocol is known.

 Returns `UnsupportedFeature` for HTTP/2 because Gun does not support
 WebSocket over HTTP/2. Path, headers, and all subprotocol tokens are
 validated before calling Gun; invalid input returns `InvalidOptions`.

```gleam
pub fn upgrade(
  connection: internal.Connection,
  protocol: connection.Protocol,
  path: String,
  headers: List(#(String, String)),
  options: UpgradeOptions
) -> Result(internal.Stream, error.GluegunError)
```

### `upgrade_options`

Construct default WebSocket upgrade options.

```gleam
pub fn upgrade_options() -> UpgradeOptions
```

### `with_closing_timeout`

Set Gun's WebSocket closing timeout.

```gleam
pub fn with_closing_timeout(
  UpgradeOptions,
  timeout: connection.Timeout
) -> UpgradeOptions
```

### `with_compress`

Enable or disable WebSocket compression.

```gleam
pub fn with_compress(
  UpgradeOptions,
  enabled: Bool
) -> UpgradeOptions
```

### `with_connect_options`

Set Gun connection options used when opening the connection.

```gleam
pub fn with_connect_options(
  Options,
  connect_options: connection.ConnectOptions
) -> Options
```

### `with_flow`

Set a positive initial WebSocket flow-control allowance.

```gleam
pub fn with_flow(
  UpgradeOptions,
  initial_flow: Int
) -> Result(UpgradeOptions, error.GluegunError)
```

### `with_headers`

Set headers sent with the WebSocket upgrade request.

```gleam
pub fn with_headers(
  Options,
  headers: List(#(String, String))
) -> Options
```

### `with_keepalive`

Set Gun's WebSocket keepalive timeout.

```gleam
pub fn with_keepalive(
  UpgradeOptions,
  timeout: connection.Timeout
) -> UpgradeOptions
```

### `with_reply_to`

Deliver upgrade and frame messages to this process. That receiver must
 await the upgrade, adopt it, receive frames, and close its socket.

```gleam
pub fn with_reply_to(
  UpgradeOptions,
  receiver: process.Pid
) -> UpgradeOptions
```

### `with_silence_pings`

Enable or disable silencing automatic ping frames.

```gleam
pub fn with_silence_pings(
  UpgradeOptions,
  enabled: Bool
) -> UpgradeOptions
```

### `with_socket`

Open a WebSocket, run a callback, then send the close frame and close
 the underlying connection.

 Scoped lifecycle helper. Use this when the WebSocket session is
 self-contained. The callback receives a reusable `Socket`. Errors from
 the callback take precedence over cleanup errors; cleanup is attempted
 even when the callback fails. If the callback panics, fails an assertion,
 or raises an Erlang exception, bounded teardown runs before re-raising
 the original exception class, reason, and stack. Cleanup cannot replace it.

```gleam
pub fn with_socket(
  host: String,
  port: Int,
  path: String,
  options: Options,
  callback: fn(Socket) -> Result(a, error.GluegunError)
) -> Result(a, error.GluegunError)
```

### `with_subprotocols`

Offer subprotocols using Gun's standard WebSocket handler. Every token is
 validated before sending; order and case are preserved.

```gleam
pub fn with_subprotocols(
  UpgradeOptions,
  protocols: List(String)
) -> UpgradeOptions
```

### `with_timeout`

Set the timeout used when awaiting connection readiness, upgrade, and frames.

```gleam
pub fn with_timeout(
  Options,
  timeout: connection.Timeout
) -> Options
```

### `with_upgrade_options`

Set Gun WebSocket upgrade options used for the upgrade request.

```gleam
pub fn with_upgrade_options(
  Options,
  upgrade_options: UpgradeOptions
) -> Options
```
