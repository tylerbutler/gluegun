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
