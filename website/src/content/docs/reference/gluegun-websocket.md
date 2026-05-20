---
title: gluegun/websocket
description: WebSocket helpers for Gun connections.
---

# `gluegun/websocket`

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
 import gluegun/connection
 import gluegun/websocket
 import gluegun/message

 let assert Ok(conn) =
   connection.options()
   |> connection.open(host: "echo.example.com", port: 80)
 let assert Ok(protocol) = connection.await_up(conn, connection.Milliseconds(5000))

 let assert Ok(stream) = websocket.upgrade_with_protocol(conn, protocol, "/ws", [])
 let assert Ok(Nil) = websocket.await_upgrade(conn, stream, connection.Milliseconds(5000))

 let assert Ok(Nil) = websocket.send(conn, stream, message.Text("hello"))
 let assert Ok(message.Text(reply)) = websocket.receive(conn, stream, connection.Milliseconds(5000))
 ```

## Types

### `Options`

High-level options for opening and upgrading a WebSocket connection.



### `Socket`

A reusable WebSocket handle.

 Wraps the upgraded Gun connection, WebSocket stream, and receive timeout so
 higher-level helpers can send and receive frames without repeating them.



### `UpgradeOptions`

Typed options for Gun WebSocket upgrades.



## Functions

### `await_upgrade`

Wait for the WebSocket upgrade confirmation (`101 Switching Protocols`).

 Call this after `upgrade/3`. Returns `Ok(Nil)` when the server confirms
 the WebSocket handshake. Returns an error on timeout, connection failure,
 or if a non-upgrade message arrives first.

```gleam
pub fn await_upgrade(gluegun/internal.Connection, gluegun/internal.Stream, gluegun/connection.Timeout) -> Result(Nil, gluegun/error.GluegunError)
```

### `connect`

Open a connection, perform a WebSocket upgrade, and return a reusable socket.

```gleam
pub fn connect(host: String, port: Int, path: String, options: gluegun/websocket.Options) -> Result(gluegun/websocket.Socket, gluegun/error.GluegunError)
```

### `options`

Construct default high-level WebSocket connection options.

```gleam
pub fn options() -> gluegun/websocket.Options
```

### `ping`

Send a ping WebSocket frame using a reusable socket.

```gleam
pub fn ping(gluegun/websocket.Socket, BitArray) -> Result(Nil, gluegun/error.GluegunError)
```

### `pong`

Send a pong WebSocket frame using a reusable socket.

```gleam
pub fn pong(gluegun/websocket.Socket, BitArray) -> Result(Nil, gluegun/error.GluegunError)
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
pub fn receive(gluegun/internal.Connection, gluegun/internal.Stream, gluegun/connection.Timeout) -> Result(gluegun/message.Frame, gluegun/error.GluegunError)
```

### `receive_app_frame`

Receive the next application frame, handling ping/pong control frames.

 Incoming pings are answered with a pong carrying the same payload. Incoming
 pongs are skipped. Text, binary, close, and close-with-reason frames are
 returned to the caller.

```gleam
pub fn receive_app_frame(gluegun/websocket.Socket) -> Result(gluegun/message.Frame, gluegun/error.GluegunError)
```

### `receive_frame`

Receive the next WebSocket frame using a reusable socket.

```gleam
pub fn receive_frame(gluegun/websocket.Socket) -> Result(gluegun/message.Frame, gluegun/error.GluegunError)
```

### `send`

Send a single WebSocket frame on the stream.

 Supported frame types: `Text`, `Binary`, `Ping`, `Pong`, `Close`,
 `CloseWithReason`. The frame is forwarded directly to Gun's `ws_send`.

```gleam
pub fn send(gluegun/internal.Connection, gluegun/internal.Stream, gluegun/message.Frame) -> Result(Nil, gluegun/error.GluegunError)
```

### `send_binary`

Send a binary WebSocket frame using a reusable socket.

```gleam
pub fn send_binary(gluegun/websocket.Socket, BitArray) -> Result(Nil, gluegun/error.GluegunError)
```

### `send_close_frame`

Send a close WebSocket frame using a reusable socket.

 This only sends the close frame; it does not close the underlying Gun
 connection.

```gleam
pub fn send_close_frame(gluegun/websocket.Socket) -> Result(Nil, gluegun/error.GluegunError)
```

### `send_frame`

Send a single WebSocket frame using a reusable socket.

```gleam
pub fn send_frame(gluegun/websocket.Socket, gluegun/message.Frame) -> Result(Nil, gluegun/error.GluegunError)
```

### `send_many`

Send one or more WebSocket frames on the stream.

 Gun accepts either a single frame or a list of frames. `send` delegates to
 this function with a one-element list.

```gleam
pub fn send_many(gluegun/internal.Connection, gluegun/internal.Stream, List(gluegun/message.Frame)) -> Result(Nil, gluegun/error.GluegunError)
```

### `send_text`

Send a text WebSocket frame using a reusable socket.

```gleam
pub fn send_text(gluegun/websocket.Socket, String) -> Result(Nil, gluegun/error.GluegunError)
```

### `upgrade`

Initiate a WebSocket upgrade on an assumed HTTP/1.1 connection.

 Prefer `upgrade_with_protocol` after `connection.await_up` when the
 connection may negotiate HTTP/2. This function keeps the original HTTP/1.1
 default path for callers that constrain the connection to HTTP/1.1.

```gleam
pub fn upgrade(gluegun/internal.Connection, String, List(#(String, String))) -> Result(gluegun/internal.Stream, gluegun/error.GluegunError)
```

### `upgrade_options`

Construct default WebSocket upgrade options.

```gleam
pub fn upgrade_options() -> gluegun/websocket.UpgradeOptions
```

### `upgrade_with_options`

Initiate a WebSocket upgrade on an assumed HTTP/1.1 connection with options.

```gleam
pub fn upgrade_with_options(gluegun/internal.Connection, String, List(#(String, String)), gluegun/websocket.UpgradeOptions) -> Result(gluegun/internal.Stream, gluegun/error.GluegunError)
```

### `upgrade_with_protocol`

Initiate a WebSocket upgrade when the negotiated protocol is known.

 Sends the WebSocket upgrade request to the server and returns the stream
 reference. Call `await_upgrade` next to confirm the handshake completed.

 Returns `InvalidMessage` for HTTP/2 because Gun does not support WebSocket
 over HTTP/2. Use this after `connection.await_up` when protocol negotiation
 may choose HTTP/2.

```gleam
pub fn upgrade_with_protocol(gluegun/internal.Connection, gluegun/connection.Protocol, String, List(#(String, String))) -> Result(gluegun/internal.Stream, gluegun/error.GluegunError)
```

### `upgrade_with_protocol_and_options`

Initiate a WebSocket upgrade with options when the negotiated protocol is known.

 Returns `InvalidMessage` for HTTP/2 because Gun does not support WebSocket
 over HTTP/2.

```gleam
pub fn upgrade_with_protocol_and_options(gluegun/internal.Connection, gluegun/connection.Protocol, String, List(#(String, String)), gluegun/websocket.UpgradeOptions) -> Result(gluegun/internal.Stream, gluegun/error.GluegunError)
```

### `with_closing_timeout`

Set Gun's WebSocket closing timeout.

```gleam
pub fn with_closing_timeout(gluegun/websocket.UpgradeOptions, gluegun/connection.Timeout) -> gluegun/websocket.UpgradeOptions
```

### `with_compress`

Enable or disable WebSocket compression.

```gleam
pub fn with_compress(gluegun/websocket.UpgradeOptions, Bool) -> gluegun/websocket.UpgradeOptions
```

### `with_connect_options`

Set Gun connection options used when opening the connection.

```gleam
pub fn with_connect_options(gluegun/websocket.Options, gluegun/connection.ConnectOptions) -> gluegun/websocket.Options
```

### `with_default_protocol_module`

Set the default WebSocket protocol callback module.

```gleam
pub fn with_default_protocol_module(gluegun/websocket.UpgradeOptions, String) -> gluegun/websocket.UpgradeOptions
```

### `with_flow`

Set the initial WebSocket flow-control allowance.

```gleam
pub fn with_flow(gluegun/websocket.UpgradeOptions, Int) -> gluegun/websocket.UpgradeOptions
```

### `with_headers`

Set headers sent with the WebSocket upgrade request.

```gleam
pub fn with_headers(gluegun/websocket.Options, List(#(String, String))) -> gluegun/websocket.Options
```

### `with_keepalive`

Set Gun's WebSocket keepalive timeout.

```gleam
pub fn with_keepalive(gluegun/websocket.UpgradeOptions, gluegun/connection.Timeout) -> gluegun/websocket.UpgradeOptions
```

### `with_protocol_module`

Add a WebSocket subprotocol callback module.

```gleam
pub fn with_protocol_module(gluegun/websocket.UpgradeOptions, String, String) -> gluegun/websocket.UpgradeOptions
```

### `with_reply_to_dynamic`

Set Gun's raw `reply_to` option.

```gleam
pub fn with_reply_to_dynamic(gluegun/websocket.UpgradeOptions, gleam/dynamic.Dynamic) -> gluegun/websocket.UpgradeOptions
```

### `with_silence_pings`

Enable or disable silencing automatic ping frames.

```gleam
pub fn with_silence_pings(gluegun/websocket.UpgradeOptions, Bool) -> gluegun/websocket.UpgradeOptions
```

### `with_socket`

Open a WebSocket, run a callback, then close the WebSocket and connection.

```gleam
pub fn with_socket(host: String, port: Int, path: String, options: gluegun/websocket.Options, callback: fn(gluegun/websocket.Socket) -> Result(a, gluegun/error.GluegunError)) -> Result(a, gluegun/error.GluegunError)
```

### `with_timeout`

Set the timeout used when awaiting connection readiness, upgrade, and frames.

```gleam
pub fn with_timeout(gluegun/websocket.Options, gluegun/connection.Timeout) -> gluegun/websocket.Options
```

### `with_tunnel_dynamic`

Set Gun's raw `tunnel` option.

```gleam
pub fn with_tunnel_dynamic(gluegun/websocket.UpgradeOptions, gleam/dynamic.Dynamic) -> gluegun/websocket.UpgradeOptions
```

### `with_upgrade_options`

Set Gun WebSocket upgrade options used for the upgrade request.

```gleam
pub fn with_upgrade_options(gluegun/websocket.Options, gluegun/websocket.UpgradeOptions) -> gluegun/websocket.Options
```

### `with_user_opts_dynamic`

Set Gun's raw `user_opts` option.

```gleam
pub fn with_user_opts_dynamic(gluegun/websocket.UpgradeOptions, gleam/dynamic.Dynamic) -> gluegun/websocket.UpgradeOptions
```
