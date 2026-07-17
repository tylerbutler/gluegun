---
title: gluegun/websocket
description: WebSocket helpers for Gun connections.
---

WebSocket helpers for Gun connections.

 ## Protocol limitations

 Gun supports WebSocket over HTTP/1.1 only. WebSocket over HTTP/2 (RFC 8441)
 is **not** supported by Gun. Call `upgrade_with_protocol` with the protocol
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

 use conn <- result.try(
   connection.options()
   |> connection.open(host: "echo.example.com", port: 80),
 )

 use protocol <- result.try(connection.await_up(conn, connection.Milliseconds(5000)))

 use stream <- result.try(websocket.upgrade_with_protocol(conn, protocol, "/ws", []))
 use _ <- result.try(websocket.await_upgrade(conn, stream, connection.Milliseconds(5000)))

 use _ <- result.try(websocket.send(conn, stream, message.Text("hello")))

 case websocket.receive(conn, stream, connection.Milliseconds(5000)) {
   Ok(message.Text(reply)) -> Ok(reply)
   Ok(_) -> Error(error.InvalidMessage("expected a text frame"))
   Error(err) -> Error(err)
 }
 ```

## Types

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
 `with_compress`, `with_default_protocol`, `with_flow`, `with_keepalive`,
 `with_protocols`, `with_silence_pings`, etc.

```gleam
pub type UpgradeOptions
```

## Functions

### `await_upgrade`

Wait for the WebSocket upgrade confirmation (`101 Switching Protocols`).

 Call this after `upgrade/3`. Returns `Ok(Nil)` when the server confirms
 the WebSocket handshake. Returns an error on timeout, connection failure,
 or if a non-upgrade message arrives first.

```gleam
pub fn await_upgrade(
  internal.Connection,
  internal.Stream,
  connection.Timeout
) -> Result(Nil, error.GluegunError)
```

### `connect`

Open a Gun connection, perform a WebSocket upgrade, and return a reusable
 socket.

 The connection is opened with the configured connect options, awaited up
 to readiness, then upgraded. If any step fails the underlying Gun
 connection is closed automatically. On success the caller owns the
 returned `Socket` and must eventually `send_close_frame` + `connection.close`
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

### `options`

Construct default high-level WebSocket connection options.

```gleam
pub fn options() -> Options
```

### `ping`

Send a ping WebSocket frame using a reusable socket.

```gleam
pub fn ping(
  Socket,
  BitArray
) -> Result(Nil, error.GluegunError)
```

### `pong`

Send a pong WebSocket frame using a reusable socket.

```gleam
pub fn pong(
  Socket,
  BitArray
) -> Result(Nil, error.GluegunError)
```

### `receive`

Receive the next WebSocket frame from the stream.

 Returns `Ok(frame)` when a WebSocket frame arrives.
 Returns `Error(InvalidMessage(...))` if a non-WebSocket message arrives
 (e.g. an HTTP response or upgrade acknowledgement that arrived out of order).
 Returns `Error(Timeout)` or stream errors on failures.

 If the upgrade acknowledgement has not yet been received, call
 `await_upgrade/3` before calling `receive`.

```gleam
pub fn receive(
  internal.Connection,
  internal.Stream,
  connection.Timeout
) -> Result(message.Frame, error.GluegunError)
```

### `receive_app_frame`

Receive the next application frame, handling ping/pong control frames.

 Incoming pings are answered with a pong carrying the same payload. Incoming
 pongs are skipped. Text, binary, close, and close-with-reason frames are
 returned to the caller.

```gleam
pub fn receive_app_frame(Socket) -> Result(message.Frame, error.GluegunError)
```

### `receive_frame`

Receive the next WebSocket frame using a reusable socket.

```gleam
pub fn receive_frame(Socket) -> Result(message.Frame, error.GluegunError)
```

### `send`

Send a single WebSocket frame on the stream.

 Supported frame types: `Text`, `Binary`, `Ping`, `Pong`, `Close`,
 `CloseWithReason`. The frame is forwarded directly to Gun's `ws_send`.

```gleam
pub fn send(
  internal.Connection,
  internal.Stream,
  message.Frame
) -> Result(Nil, error.GluegunError)
```

### `send_binary`

Send a binary WebSocket frame using a reusable socket.

```gleam
pub fn send_binary(
  Socket,
  BitArray
) -> Result(Nil, error.GluegunError)
```

### `send_close_frame`

Send a close WebSocket frame using a reusable socket.

 This only sends the close frame; it does not close the underlying Gun
 connection. Follow with `connection.close(socket.connection)` or use
 `with_socket` for automatic teardown.

```gleam
pub fn send_close_frame(Socket) -> Result(Nil, error.GluegunError)
```

### `send_frame`

Send a single WebSocket frame using a reusable socket.

```gleam
pub fn send_frame(
  Socket,
  message.Frame
) -> Result(Nil, error.GluegunError)
```

### `send_many`

Send one or more WebSocket frames on the stream.

 Gun accepts either a single frame or a list of frames. `send` delegates to
 this function with a one-element list.

```gleam
pub fn send_many(
  internal.Connection,
  internal.Stream,
  List(message.Frame)
) -> Result(Nil, error.GluegunError)
```

### `send_text`

Send a text WebSocket frame using a reusable socket.

```gleam
pub fn send_text(
  Socket,
  String
) -> Result(Nil, error.GluegunError)
```

### `upgrade`

Initiate a WebSocket upgrade on an assumed HTTP/1.1 connection.

 Prefer `upgrade_with_protocol` after `connection.await_up` when the
 connection may negotiate HTTP/2. This function keeps the original HTTP/1.1
 default path for callers that constrain the connection to HTTP/1.1.

```gleam
pub fn upgrade(
  internal.Connection,
  String,
  List(#(String, String))
) -> Result(internal.Stream, error.GluegunError)
```

### `upgrade_options`

Construct default WebSocket upgrade options.

```gleam
pub fn upgrade_options() -> UpgradeOptions
```

### `upgrade_with_options`

Initiate a WebSocket upgrade on an assumed HTTP/1.1 connection with options.

```gleam
pub fn upgrade_with_options(
  internal.Connection,
  String,
  List(#(String, String)),
  UpgradeOptions
) -> Result(internal.Stream, error.GluegunError)
```

### `upgrade_with_protocol`

Initiate a WebSocket upgrade when the negotiated protocol is known.

 Sends the WebSocket upgrade request to the server and returns the stream
 reference. Call `await_upgrade` next to confirm the handshake completed.

 Returns `UnsupportedFeature` for HTTP/2 because Gun does not support
 WebSocket over HTTP/2. Use this after `connection.await_up` when protocol
 negotiation may choose HTTP/2.

```gleam
pub fn upgrade_with_protocol(
  internal.Connection,
  connection.Protocol,
  String,
  List(#(String, String))
) -> Result(internal.Stream, error.GluegunError)
```

### `upgrade_with_protocol_and_options`

Initiate a WebSocket upgrade with options when the negotiated protocol is known.

 Returns `UnsupportedFeature` for HTTP/2 because Gun does not support
 WebSocket over HTTP/2.

```gleam
pub fn upgrade_with_protocol_and_options(
  internal.Connection,
  connection.Protocol,
  String,
  List(#(String, String)),
  UpgradeOptions
) -> Result(internal.Stream, error.GluegunError)
```

### `with_closing_timeout`

Set Gun's WebSocket closing timeout.

```gleam
pub fn with_closing_timeout(
  UpgradeOptions,
  connection.Timeout
) -> UpgradeOptions
```

### `with_compress`

Enable or disable WebSocket compression.

```gleam
pub fn with_compress(
  UpgradeOptions,
  Bool
) -> UpgradeOptions
```

### `with_connect_options`

Set Gun connection options used when opening the connection.

```gleam
pub fn with_connect_options(
  Options,
  connection.ConnectOptions
) -> Options
```

### `with_default_protocol_module`

Set the default WebSocket protocol callback module.

```gleam
pub fn with_default_protocol_module(
  UpgradeOptions,
  String
) -> UpgradeOptions
```

### `with_flow`

Set the initial WebSocket flow-control allowance.

```gleam
pub fn with_flow(
  UpgradeOptions,
  Int
) -> UpgradeOptions
```

### `with_headers`

Set headers sent with the WebSocket upgrade request.

```gleam
pub fn with_headers(
  Options,
  List(#(String, String))
) -> Options
```

### `with_keepalive`

Set Gun's WebSocket keepalive timeout.

```gleam
pub fn with_keepalive(
  UpgradeOptions,
  connection.Timeout
) -> UpgradeOptions
```

### `with_protocol_module`

Add a WebSocket subprotocol callback module.

```gleam
pub fn with_protocol_module(
  UpgradeOptions,
  String,
  String
) -> UpgradeOptions
```

### `with_silence_pings`

Enable or disable silencing automatic ping frames.

```gleam
pub fn with_silence_pings(
  UpgradeOptions,
  Bool
) -> UpgradeOptions
```

### `with_socket`

Open a WebSocket, run a callback, then send the close frame and close
 the underlying connection.

 Scoped lifecycle helper. Use this when the WebSocket session is
 self-contained. The callback receives a reusable `Socket`. Errors from
 the callback take precedence over cleanup errors; cleanup is attempted
 even when the callback fails.

```gleam
pub fn with_socket(
  host: String,
  port: Int,
  path: String,
  options: Options,
  callback: fn(Socket) -> Result(a, error.GluegunError)
) -> Result(a, error.GluegunError)
```

### `with_timeout`

Set the timeout used when awaiting connection readiness, upgrade, and frames.

```gleam
pub fn with_timeout(
  Options,
  connection.Timeout
) -> Options
```

### `with_upgrade_options`

Set Gun WebSocket upgrade options used for the upgrade request.

```gleam
pub fn with_upgrade_options(
  Options,
  UpgradeOptions
) -> Options
```
