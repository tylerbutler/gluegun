---
title: gluegun
description: Minimal common-path facade for the Gluegun HTTP client wrapper.
---

# `gluegun`

Minimal common-path facade for the Gluegun HTTP client wrapper.

 For full functionality import the submodules (`gluegun/connection`,
 `gluegun/request`, `gluegun/client`, `gluegun/websocket`,
 `gluegun/message`, `gluegun/response`, `gluegun/error`).

## Functions

### `await_up`

Wait until a Gun connection is up.

```gleam
pub fn await_up(gluegun/internal.Connection, gluegun/connection.Timeout) -> Result(gluegun/connection.Protocol, gluegun/error.GluegunError)
```

### `body_text`

Decode a response body as UTF-8 text.

```gleam
pub fn body_text(gluegun/response.Response) -> Result(String, gluegun/error.GluegunError)
```

### `connection_options`

Construct default connection options.

```gleam
pub fn connection_options() -> gluegun/connection.ConnectOptions
```

### `new_request`

Construct a collected HTTP request command.

```gleam
pub fn new_request(gluegun/request.Method, String) -> gluegun/client.Request
```

### `open`

Open a Gun connection.

```gleam
pub fn open(gluegun/connection.ConnectOptions, host: String, port: Int) -> Result(gluegun/internal.Connection, gluegun/error.GluegunError)
```

### `send`

Send a collected HTTP request command.

```gleam
pub fn send(gluegun/client.Request, connection: gluegun/internal.Connection) -> Result(gluegun/response.Response, gluegun/error.GluegunError)
```

### `tls_options`

Construct default TLS options.

```gleam
pub fn tls_options() -> gluegun/tls.TlsOptions
```

### `websocket_connect`

Open a connection, perform a WebSocket upgrade, and return a reusable socket.

```gleam
pub fn websocket_connect(host: String, port: Int, path: String, options: gluegun/websocket.Options) -> Result(gluegun/websocket.Socket, gluegun/error.GluegunError)
```

### `websocket_options`

Construct default high-level WebSocket connection options.

```gleam
pub fn websocket_options() -> gluegun/websocket.Options
```

### `websocket_receive_app_frame`

Receive the next application WebSocket frame, handling ping/pong frames.

```gleam
pub fn websocket_receive_app_frame(gluegun/websocket.Socket) -> Result(gluegun/message.Frame, gluegun/error.GluegunError)
```

### `websocket_send_close_frame`

Send a close WebSocket frame using a reusable socket.

```gleam
pub fn websocket_send_close_frame(gluegun/websocket.Socket) -> Result(Nil, gluegun/error.GluegunError)
```

### `websocket_send_text`

Send a text WebSocket frame using a reusable socket.

```gleam
pub fn websocket_send_text(gluegun/websocket.Socket, String) -> Result(Nil, gluegun/error.GluegunError)
```

### `websocket_with_socket`

Open a WebSocket, run a callback, then close the WebSocket and connection.

```gleam
pub fn websocket_with_socket(host: String, port: Int, path: String, options: gluegun/websocket.Options, callback: fn(gluegun/websocket.Socket) -> Result(a, gluegun/error.GluegunError)) -> Result(a, gluegun/error.GluegunError)
```

### `with_connect_timeout`

Set connect timeout on connection options.

```gleam
pub fn with_connect_timeout(gluegun/connection.ConnectOptions, timeout: gluegun/connection.Timeout) -> gluegun/connection.ConnectOptions
```

### `with_protocols`

Set protocol preferences on connection options.

```gleam
pub fn with_protocols(gluegun/connection.ConnectOptions, protocols: List(gluegun/connection.Protocol)) -> gluegun/connection.ConnectOptions
```

### `with_retry`

Set Gun retry timeout on connection options.

```gleam
pub fn with_retry(gluegun/connection.ConnectOptions, retry: gluegun/connection.Timeout) -> gluegun/connection.ConnectOptions
```

### `with_tls_opts`

Set TLS options on connection options.

```gleam
pub fn with_tls_opts(gluegun/connection.ConnectOptions, tls_opts: gluegun/tls.TlsOptions) -> gluegun/connection.ConnectOptions
```

### `with_transport`

Set the transport on connection options.

```gleam
pub fn with_transport(gluegun/connection.ConnectOptions, transport: gluegun/connection.Transport) -> gluegun/connection.ConnectOptions
```
