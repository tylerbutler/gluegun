---
title: Message Flow
description: Understand how Gluegun maps Gun stream messages into Gleam values.
---

Gun sends asynchronous messages to the process that owns or awaits a stream. Gluegun keeps that model visible and decodes those messages into typed Gleam values.

The main flow is:

1. Open a connection with `gluegun/connection`.
2. Start a stream with `gluegun/request`.
3. Await stream messages with `gluegun/message`.
4. Pattern match on `message.Response`, `message.Data`, `message.Trailers`, WebSocket frames, or errors.

High-level `gluegun/client` helpers use this flow internally for regular HTTP responses. They are intentionally scoped to one request and collect the complete body in memory.

For advanced Gun behavior, keep using the lower-level `request` and `message` APIs so your application can decide how to handle streaming, flow control, cancellation, trailers, and protocol-specific events.

## `message.await` versus `message.await_body`

- `message.await(conn, stream, timeout)` returns the *next* message for a stream as a typed `Message`. Use it in a loop to handle `Inform`, `Response`, `Data`, `Trailers`, `Push`, `Upgrade`, and `WebSocket` values explicitly. This is the right choice for streaming, server push, upgrade flows, or any case where you want to apply backpressure.
- `message.await_body(conn, stream, timeout)` is a convenience that drains body chunks until `Fin` and returns the concatenated bytes. It must be called *after* the `Response` message has been received (e.g. via a prior `await`). The whole body is held in memory.

For chunked bodies, see the [streaming guide](/guides/streaming/). For WebSocket upgrade flows, see the [websockets guide](/guides/websockets/).

See the [message reference](/reference/gluegun-message/) for every decoded message variant.
