---
title: gluegun/message
description: Decoding and awaiting asynchronous Gun stream messages.
---

# `gluegun/message`

Decoding and awaiting asynchronous Gun stream messages.

 Gun sends HTTP, HTTP/2 push, upgrade, and WebSocket events as Erlang
 messages. This module decodes those messages into Gleam types for callers
 using lower-level streaming or advanced flows.

## Types

### `Frame`

WebSocket frames delivered inside Gun stream messages.

 `Close` represents a plain close with no status code or reason.
 `CloseWithReason` carries a numeric close code and an opaque reason payload.

 On the wire Gun delivers `close` (atom) as `Close` and
 `{close, Code, Reason}` as `CloseWithReason`.

- `Text(String)`
- `Binary(BitArray)`
- `Ping(BitArray)`
- `Pong(BitArray)`
- `Close()`
- `CloseWithReason(Int, BitArray)`

### `Message`

Gun HTTP stream messages delivered by the Erlang Gun client.

 This type is closed; new variants are a breaking change. Pin to a major
 version.

- `Inform(Int, List(#(String, String)))`
- `Response(gluegun/fin.Fin, Int, List(#(String, String)))`
- `Data(gluegun/fin.Fin, BitArray)`
- `Trailers(List(#(String, String)))`
- `Push(gluegun/internal.Stream, gluegun/request.Method, String, List(#(String, String)))`
- `Upgrade(List(String), List(#(String, String)))`
- `WebSocket(gluegun/message.Frame)`

## Type aliases

### `GluegunError`

Alias for `gluegun/error.GluegunError`.

```gleam
pub type GluegunError = Unknown
```

### `Header`

Alias for `gluegun/request.Header` used in decoded messages.

```gleam
pub type Header = Unknown
```

### `Method`

Alias for `gluegun/request.Method` used in decoded messages.

```gleam
pub type Method = Unknown
```

## Functions

### `await`

Await the next Gun message for a stream.

```gleam
pub fn await(gluegun/internal.Connection, gluegun/internal.Stream, gluegun/connection.Timeout) -> Result(gluegun/message.Message, gluegun/error.GluegunError)
```

### `await_body`

Await and collect the full response body for a stream.

```gleam
pub fn await_body(gluegun/internal.Connection, gluegun/internal.Stream, gluegun/connection.Timeout) -> Result(BitArray, gluegun/error.GluegunError)
```

### `decode`

Decode a raw Erlang Gun message into a typed Gleam message.

```gleam
pub fn decode(gleam/dynamic.Dynamic) -> Result(gluegun/message.Message, gluegun/error.GluegunError)
```
