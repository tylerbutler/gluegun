---
title: gluegun/message
description: Decoding and awaiting asynchronous Gun stream messages.
---

Decoding and awaiting asynchronous Gun stream messages.

 Gun sends HTTP, HTTP/2 push, upgrade, and WebSocket events as Erlang
 messages. This module decodes those messages into Gleam types for callers
 using lower-level streaming or advanced flows.

## Types

### `Frame`

WebSocket frames delivered inside Gun stream messages.

 On the wire Gun delivers `close` (atom) as `Close` and
 `{close, Code, Reason}` as `CloseWithReason`.

```gleam
pub type Frame {
  Text(String)
  Binary(BitArray)
  Ping(BitArray)
  Pong(BitArray)
  Close
  CloseWithReason(
    code: Int,
    reason: BitArray
  )
}
```

#### Constructors

##### `Text(String)`

A UTF-8 text frame. Gun validates the payload as UTF-8 before delivery.

##### `Binary(BitArray)`

A binary frame. The payload is an opaque byte string.

##### `Ping(BitArray)`

A ping control frame. Reply with `Pong` to keep the connection alive.

##### `Pong(BitArray)`

A pong control frame. Usually delivered in response to a `Ping`.

##### `Close`

A close control frame with no status code or reason.

##### `CloseWithReason(code: Int, reason: BitArray)`

A close control frame carrying a numeric close code and opaque reason
 payload (RFC 6455 §5.5.1).

### `Message`

Gun HTTP stream messages delivered by the Erlang Gun client.

 Sequencing for a normal HTTP response:
 zero or more `Inform` (1xx) → one `Response` → zero or more `Data` (until
 `Fin`) → optional `Trailers`. `Push` and `Upgrade` may appear for HTTP/2
 server push and protocol switching. `WebSocket` only appears after a
 successful upgrade.

 This type is closed; new variants are a breaking change. Pin to a major
 version.

```gleam
pub type Message {
  Inform(
    status: Int,
    headers: List(#(String, String))
  )
  Response(
    fin: fin.Fin,
    status: Int,
    headers: List(#(String, String))
  )
  Data(
    fin: fin.Fin,
    data: BitArray
  )
  Trailers(headers: List(#(String, String)))
  Push(
    stream: internal.Stream,
    method: request.Method,
    uri: String,
    headers: List(#(String, String))
  )
  Upgrade(
    protocols: List(String),
    headers: List(#(String, String))
  )
  WebSocket(frame: Frame)
}
```

#### Constructors

##### `Inform(status: Int, headers: List(#(String, String)))`

A 1xx informational response. May appear multiple times before the
 final `Response`.

##### `Response(fin: fin.Fin, status: Int, headers: List(#(String, String)))`

The final HTTP response headers. `fin` is `Fin` when there is no body.

##### `Data(fin: fin.Fin, data: BitArray)`

A response body chunk. `fin` is `Fin` on the last chunk.

##### `Trailers(headers: List(#(String, String)))`

Trailing headers delivered after the body (HTTP/1.1 trailers or HTTP/2
 trailer frames).

##### `Push(stream: internal.Stream, method: request.Method, uri: String, headers: List(#(String, String)))`

An HTTP/2 server push. The `stream` is a new stream the caller may
 await or cancel.

##### `Upgrade(protocols: List(String), headers: List(#(String, String)))`

A successful protocol upgrade. Subsequent messages on this stream use
 the new protocol (e.g. WebSocket).

##### `WebSocket(frame: Frame)`

A decoded WebSocket frame. Only delivered after an upgrade.

## Type aliases

### `GluegunError`

Alias for `gluegun/error.GluegunError`.

```gleam
pub type GluegunError = error.GluegunError
```

### `Header`

Alias for `gluegun/request.Header` used in decoded messages.

```gleam
pub type Header = #(String, String)
```

### `Method`

Alias for `gluegun/request.Method` used in decoded messages.

```gleam
pub type Method = request.Method
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
pub fn await(
  internal.Connection,
  internal.Stream,
  connection.Timeout
) -> Result(Message, error.GluegunError)
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
pub fn await_body(
  internal.Connection,
  internal.Stream,
  connection.Timeout
) -> Result(BitArray, error.GluegunError)
```

### `decode`

Decode a raw Erlang Gun message into a typed Gleam message.

 Useful when receiving Gun messages outside Gluegun's helpers (e.g. inside
 a custom `receive` loop). Returns `DecodeError` if the dynamic value is
 not a recognized Gun message shape.

```gleam
pub fn decode(dynamic.Dynamic) -> Result(Message, error.GluegunError)
```
