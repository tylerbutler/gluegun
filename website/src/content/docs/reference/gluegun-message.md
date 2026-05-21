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

 Sequencing for a normal HTTP response:
 zero or more `Inform` (1xx) → one `Response` → zero or more `Data` (until
 `Fin`) → optional `Trailers`. `Push` and `Upgrade` may appear for HTTP/2
 server push and protocol switching. `WebSocket` only appears after a
 successful upgrade.

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
pub type GluegunError = gluegun/error.GluegunError
```

### `Header`

Alias for `gluegun/request.Header` used in decoded messages.

```gleam
pub type Header = #(String, String)
```

### `Method`

Alias for `gluegun/request.Method` used in decoded messages.

```gleam
pub type Method = gluegun/request.Method
```

## Functions

### `await`

Await the next Gun message for a stream.

 Blocks the calling process until a message arrives, the stream errors,
 or `timeout` elapses. Messages arrive in the order described on
 `Message`: `Inform`* → `Response` → `Data`* → `Trailers`?. Use this for
 streaming responses, server push, or any flow where you need messages as
 they arrive.

 Errors: `Timeout`, `ConnectionDown`, `StreamError`, `DecodeError`.

```gleam
pub fn await(gluegun/internal.Connection, gluegun/internal.Stream, gluegun/connection.Timeout) -> Result(gluegun/message.Message, gluegun/error.GluegunError)
```

### `await_body`

Await and collect the full response body for a stream.

 Drains body chunks until the final `Fin` and returns the concatenated
 payload. Headers must already have been consumed (e.g. via a prior
 `await` that returned `Response`). For incremental access use `await`
 directly. The full body is held in memory; use the lower-level loop for
 very large responses.

 Errors: `Timeout`, `ConnectionDown`, `StreamError`.

```gleam
pub fn await_body(gluegun/internal.Connection, gluegun/internal.Stream, gluegun/connection.Timeout) -> Result(BitArray, gluegun/error.GluegunError)
```

### `decode`

Decode a raw Erlang Gun message into a typed Gleam message.

 Useful when receiving Gun messages outside Gluegun's helpers (e.g. inside
 a custom `receive` loop). Returns `DecodeError` if the dynamic value is
 not a recognized Gun message shape.

```gleam
pub fn decode(gleam/dynamic.Dynamic) -> Result(gluegun/message.Message, gluegun/error.GluegunError)
```
