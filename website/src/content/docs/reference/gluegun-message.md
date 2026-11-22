---
title: gluegun/message
description: Decoding and awaiting asynchronous Gun stream messages.
---

Decoding and awaiting asynchronous Gun stream messages.

 Gun sends HTTP, HTTP/2 push, upgrade, and WebSocket events as Erlang
 messages. This module decodes those messages into Gleam types for callers
 using lower-level streaming or advanced flows.

## Types

### `Envelope`

A decoded `Message` paired with the connection and stream Gun says it
 belongs to.

 Gun's mailbox tuples (`gun_response`, `gun_data`, `gun_inform`,
 `gun_trailers`, `gun_push`, `gun_upgrade`, `gun_ws`) always name the
 connection process and stream reference a message came from. `decode`
 preserves both alongside the decoded `Message` so a process that owns
 several concurrent streams — for example an HTTP/2 connection with
 server push, or several requests sharing one `reply_to` process — can
 attribute each message to the right stream instead of assuming messages
 arrive for whichever stream the caller currently has in mind.

 `stream` names the stream that *delivered* the message; for `Push` it is
 the existing stream the server pushed on, not the new stream carried
 inside `message.Push`.

```gleam
pub type Envelope {
  Envelope(
    connection: connection.Connection,
    stream: request.Stream,
    message: Message
  )
}
```

### `Event`

A Gun mailbox event with its source identity.

 `ConnectionDown` describes a disconnect, not necessarily a final exit:
 Gun can reconnect when retry is enabled. Stream failures include malformed
 payloads with valid source handles, so callers can route decode errors too.

```gleam
pub type Event {
  StreamMessage(Envelope)
  ConnectionUp(
    connection: connection.Connection,
    protocol: EventProtocol
  )
  ConnectionDown(
    connection: connection.Connection,
    protocol: EventProtocol,
    error: error.GluegunError,
    killed_streams: List(request.Stream)
  )
  TunnelUp(
    connection: connection.Connection,
    stream: request.Stream,
    protocol: EventProtocol
  )
  StreamFailure(
    connection: connection.Connection,
    stream: request.Stream,
    error: error.GluegunError
  )
  ConnectionFailure(
    connection: connection.Connection,
    error: error.GluegunError
  )
}
```

### `EventProtocol`

Protocol names Gun reports in connection and tunnel lifecycle messages.

 Separate from `connection.Protocol`: Gun can report `ws`, `raw`, or `socks`
 after switching away from HTTP.

```gleam
pub type EventProtocol {
  Http1
  Http2
  WebSocketProtocol
  Raw
  Socks
}
```

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

### `GunMessage`

A raw Gun stream message, exactly as Gun delivers it to the process that
 owns the stream.

 This external type has no Gleam constructors. Use `select` to receive typed
 events without caller FFI, or `decode` / `decode_event` when an Erlang
 integration already supplies raw Gun messages.

```gleam
pub type GunMessage
```

### `Message`

Gun HTTP stream messages delivered by the Erlang Gun client.

 A normal HTTP response starts with zero or more `Inform` (1xx) messages,
 then follows one of three sequences:

 - `Response(Fin, ...)`: headers only.
 - `Response(NoFin, ...)`, zero or more `Data(NoFin, ...)`, then
   `Data(Fin, ...)`: a body without trailers.
 - `Response(NoFin, ...)`, zero or more `Data(NoFin, ...)`, then
   `Trailers(...)`: a response with trailers.

 Stop receiving for that response at `Response(Fin, ...)`, `Data(Fin, ...)`,
 or `Trailers(...)`. Trailers do not follow `Fin`, and a response with
 trailers has no `Data(Fin, ...)` message.

 `Push` and `Upgrade` may appear for HTTP/2 server push and protocol
 switching. `WebSocket` only appears after a successful upgrade.

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
    stream: request.Stream,
    method: http.Method,
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

The final HTTP response headers. `Fin` ends the response with no body
 or trailers. `NoFin` means body chunks or trailers follow.

##### `Data(fin: fin.Fin, data: BitArray)`

A response body chunk. `Fin` ends the response without trailers.
 With trailers, all body chunks use `NoFin`.

##### `Trailers(headers: List(#(String, String)))`

Trailing headers that end the response (HTTP/1.1 trailers or HTTP/2
 trailer frames). They follow `Response(NoFin, ...)` and zero or more
 `Data(NoFin, ...)` messages, with no separate `Data(Fin, ...)`.

##### `Push(stream: request.Stream, method: http.Method, uri: String, headers: List(#(String, String)))`

An HTTP/2 server push. The `stream` is a new stream the caller may
 await or cancel. Method names are case-sensitive: `GET` becomes
 `gleam/http.Get`, while `get` becomes `gleam/http.Other("get")`.

##### `Upgrade(protocols: List(String), headers: List(#(String, String)))`

A successful protocol upgrade. Subsequent messages on this stream use
 the new protocol (e.g. WebSocket).

##### `WebSocket(frame: Frame)`

A decoded WebSocket frame. Only delivered after an upgrade.

## Functions

### `await`

Await the next Gun message for a stream.

 Blocks the calling process until a message arrives, the stream errors,
 or `timeout` elapses. Messages arrive in the order described on
 `Message`. For a normal HTTP response, stop at `Response(Fin, ...)`,
 `Data(Fin, ...)`, or `Trailers(...)`; do not await another message for
 that response. Use this for streaming responses, server push, or any flow
 where you need messages as they arrive.

 Errors: `Timeout`, `ConnectionDown`, `ConnectionError`, `StreamError`,
 `InvalidMessage`, `ErlangError`.

```gleam
pub fn await(
  connection.Connection,
  request.Stream,
  connection.Timeout
) -> Result(Message, error.GluegunError)
```

### `await_body`

Await and collect the full response body for a stream.

 Drains body chunks until `Data(Fin, ...)` or `Trailers(...)` and returns
 the concatenated payload. Call only after `Response(NoFin, ...)` (e.g.
 from a prior `await`); `Response(Fin, ...)` is already complete and has
 no body to await. When the response ends with trailers,
 the collected body is returned and the trailer headers are dropped; use
 `await` if you need them. For incremental access use `await`
 directly. The full body is held in memory; use the lower-level loop for
 very large responses.

 Errors: `Timeout`, `ConnectionDown`, `ConnectionError`, `StreamError`,
 `ErlangError`.

```gleam
pub fn await_body(
  connection.Connection,
  request.Stream,
  connection.Timeout
) -> Result(BitArray, error.GluegunError)
```

### `decode`

Decode a raw Erlang Gun mailbox message into a typed `Message`, paired
 with the connection and stream it belongs to.

 Useful when receiving Gun messages outside Gluegun's helpers (for example
 inside a custom `receive` loop that hands the message to Gluegun through
 your own Erlang FFI). Accepts the mailbox tuples Gun sends to the stream
 owner (`gun_response`, `gun_data`, `gun_inform`, `gun_trailers`,
 `gun_push`, `gun_upgrade`, `gun_ws`). For `gun_error`, returns
 `StreamError` or `ConnectionError` according to the message's scope.
 For `gun_down`, returns `ConnectionDown` with Gun's reason.
 Error results do not include an envelope. Returns `DecodeError` for an
 unrecognized or malformed message, including the shorter terms returned
 by `gun:await/3`.

```gleam
pub fn decode(GunMessage) -> Result(Envelope, error.GluegunError)
```

### `decode_event`

Decode stream, lifecycle, and error mailbox tuples without losing source
 identity. Reuses `decode` for stream payloads and the existing Gun error
 conversion. Invalid source handles or lifecycle fields return `DecodeError`.
 This does not change `decode` or add variants to `Message`.

```gleam
pub fn decode_event(GunMessage) -> Result(Event, error.GluegunError)
```

### `select`

Add supported Gun mailbox tuples to an application selector.

 Selects stream tuples plus `gun_up`, `gun_down`, `gun_tunnel_up`, and both
 `gun_error` shapes by tag and arity, across this receiver's whole mailbox.
 Route events by connection and stream; this cannot filter one connection.
 Malformed supported tuples reach the mapping as typed errors. Other tags,
 unsupported arities, application subjects, and external `DOWN` messages
 remain for their own handlers. Register the Gun handlers once per selector.

 The actor must open its connection in its own init function. For WebSocket
 envelopes, call `websocket.record_frame` before handling the frame so close
 can track peer-close and finite flow credit.

```gleam
pub fn select(
  process.Selector(a),
  fn(Result(Event, error.GluegunError)) -> a
) -> process.Selector(a)
```
