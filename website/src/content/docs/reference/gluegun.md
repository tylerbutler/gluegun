---
title: gluegun
description: Minimal common-path facade for the Gluegun HTTP client wrapper.
---

Minimal common-path facade for the Gluegun HTTP client wrapper.

 For full functionality import the submodules (`gluegun/connection`,
 `gluegun/request`, `gluegun/client`, `gluegun/websocket`,
 `gluegun/message`, `gluegun/response`, `gluegun/error`).

## Functions

### `await_up`

Wait until a Gun connection is up.

```gleam
pub fn await_up(
  internal.Connection,
  connection.Timeout
) -> Result(connection.Protocol, error.GluegunError)
```

### `body_text`

Decode a response body as UTF-8 text.

```gleam
pub fn body_text(response.Response) -> Result(String, error.GluegunError)
```

### `connection_options`

Construct default connection options.

```gleam
pub fn connection_options() -> connection.ConnectOptions
```

### `method_to_string`

Convert a request method to an HTTP method string.

```gleam
pub fn method_to_string(request.Method) -> String
```

### `name`

Return the package name.

```gleam
pub fn name() -> String
```

### `new_request`

Construct a `Request` builder.

```gleam
pub fn new_request(
  request.Method,
  String
) -> client.Request
```

### `normalize_headers`

Normalize header names for Gun.

```gleam
pub fn normalize_headers(List(#(String, String))) -> List(#(String, String))
```

### `open`

Open a Gun connection.

```gleam
pub fn open(
  connection.ConnectOptions,
  host: String,
  port: Int
) -> Result(internal.Connection, error.GluegunError)
```

### `response`

Construct a collected HTTP response.

```gleam
pub fn response(
  status: Int,
  headers: List(#(String, String)),
  body: BitArray,
  trailers: List(#(String, String))
) -> response.Response
```

### `send`

Send a `Request` on an open connection.

```gleam
pub fn send(
  client.Request,
  connection: internal.Connection
) -> Result(response.Response, error.GluegunError)
```

### `tls_options`

Construct default TLS options.

```gleam
pub fn tls_options() -> tls.TlsOptions
```

### `websocket_connect`

Open a connection, perform a WebSocket upgrade, and return a reusable socket.

```gleam
pub fn websocket_connect(
  host: String,
  port: Int,
  path: String,
  options: websocket.Options
) -> Result(websocket.Socket, error.GluegunError)
```

### `websocket_options`

Construct default high-level WebSocket connection options.

```gleam
pub fn websocket_options() -> websocket.Options
```

### `websocket_receive_app_frame`

Receive the next application WebSocket frame, handling ping/pong frames.

```gleam
pub fn websocket_receive_app_frame(websocket.Socket) -> Result(message.Frame, error.GluegunError)
```

### `websocket_send_close_frame`

Send a close WebSocket frame using a reusable socket.

```gleam
pub fn websocket_send_close_frame(websocket.Socket) -> Result(Nil, error.GluegunError)
```

### `websocket_send_text`

Send a text WebSocket frame using a reusable socket.

```gleam
pub fn websocket_send_text(
  websocket.Socket,
  String
) -> Result(Nil, error.GluegunError)
```

### `websocket_with_socket`

Open a WebSocket, run a callback, then close the WebSocket and connection.

```gleam
pub fn websocket_with_socket(
  host: String,
  port: Int,
  path: String,
  options: websocket.Options,
  callback: fn(websocket.Socket) -> Result(a, error.GluegunError)
) -> Result(a, error.GluegunError)
```

### `with_connect_timeout`

Set connect timeout on connection options.

```gleam
pub fn with_connect_timeout(
  connection.ConnectOptions,
  timeout: connection.Timeout
) -> connection.ConnectOptions
```

### `with_protocols`

Set protocol preferences on connection options.

```gleam
pub fn with_protocols(
  connection.ConnectOptions,
  protocols: List(connection.Protocol)
) -> connection.ConnectOptions
```

### `with_retry`

Set Gun retry timeout on connection options.

```gleam
pub fn with_retry(
  connection.ConnectOptions,
  retry: connection.Timeout
) -> connection.ConnectOptions
```

### `with_tls_opts`

Set TLS options on connection options.

```gleam
pub fn with_tls_opts(
  connection.ConnectOptions,
  tls_opts: tls.TlsOptions
) -> connection.ConnectOptions
```

### `with_transport`

Set the transport on connection options.

```gleam
pub fn with_transport(
  connection.ConnectOptions,
  transport: connection.Transport
) -> connection.ConnectOptions
```
