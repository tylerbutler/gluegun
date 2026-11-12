---
title: gluegun
description: A small HTTP facade for Gluegun.
---

A small HTTP facade for Gluegun.

 Construct a timeout and connection options, open and await the connection,
 then build and send a request. Always close or terminate the connection,
 including after an error. For request customization use `gluegun/client`;
 for streaming use `gluegun/request` and `gluegun/message`.
 WebSockets have a complete lifecycle API in `gluegun/websocket`.

## Functions

### `await_up`

Wait for connection readiness and the negotiated HTTP protocol.

```gleam
pub fn await_up(
  internal.Connection,
  connection.Timeout
) -> Result(connection.Protocol, error.GluegunError)
```

### `body_text`

Decode the response body as UTF-8.

```gleam
pub fn body_text(response.Response(BitArray)) -> Result(String, error.GluegunError)
```

### `close`

Stop the connection through Gun's supervisor; this does not flush messages.

```gleam
pub fn close(internal.Connection) -> Result(Nil, error.GluegunError)
```

### `connection_options`

Construct default connection options, with no automatic retries.

```gleam
pub fn connection_options() -> connection.ConnectOptions
```

### `infinity`

Construct an unlimited timeout.

```gleam
pub fn infinity() -> connection.Timeout
```

### `milliseconds`

Construct a timeout from 0 through 4_294_967_295 milliseconds, inclusive.

 Returns `InvalidOptions` outside this range. Use `infinity()` for no limit.

```gleam
pub fn milliseconds(Int) -> Result(connection.Timeout, error.GluegunError)
```

### `new_request`

Construct a request with an empty body and a five-second total budget.

```gleam
pub fn new_request(
  http.Method,
  String
) -> client.Request
```

### `open`

Open a connection. Await readiness before sending a request.

```gleam
pub fn open(
  connection.ConnectOptions,
  host: String,
  port: Int
) -> Result(internal.Connection, error.GluegunError)
```

### `send`

Send a request and collect its complete HTTP response in memory.

```gleam
pub fn send(
  client.Request,
  connection: internal.Connection
) -> Result(response.Response(BitArray), error.GluegunError)
```

### `shutdown`

Request graceful asynchronous shutdown.

```gleam
pub fn shutdown(internal.Connection) -> Result(Nil, error.GluegunError)
```

### `terminate`

Force connection exit and flush its queued messages from this receiver.

```gleam
pub fn terminate(internal.Connection) -> Result(Nil, error.GluegunError)
```
