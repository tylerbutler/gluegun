---
title: Limitations
description: Know the current boundaries of Gluegun.
---

## Erlang target only

Gluegun is an interface to Erlang Gun. It is not available on the JavaScript target.

## Connection ownership is important

Gun process ownership is important. Requests and WebSocket frames are asynchronous messages. Gun sends them to the process that owns, or waits for, the Gun stream, unless request options send replies to a different process. The high-level `client` functions read those messages on the calling process during `send`, then return. They do not start a separate consumer process.

## `close` and `shutdown`

Use `connection.close` to stop a connection through Gun's supervisor. It waits for process exit, but does not drain HTTP streams or flush your mailbox. `connection.shutdown` requests graceful shutdown without waiting; it cannot interrupt blocked setup. Use `connection.terminate` for deadline cleanup: it forces exit, waits, then flushes the caller's Gun messages. See [Message Flow](/advanced/message-flow/#close-and-shutdown).

## Flow credit is not a byte limit

Finite initial flow credit counts data messages. Gun and OTP can allocate socket buffers or parse several frames before flow control pauses reads or window updates. Check actual bytes before retaining data; do not treat credit as a strict memory cap. See [Streaming](/guides/streaming/#finite-response-credit).

## High-level client functions collect bodies in memory

Use the low-level `request` and `message` APIs for streams or advanced Gun flows. The `client` functions are for usual HTTP responses that can be collected in memory.

## WebSocket over HTTP/2 is not supported

Gun supports WebSocket over HTTP/1.1. `websocket.upgrade_with_protocol` checks the protocol that `connection.await_up` returns. It rejects HTTP/2 before it calls Gun.

## The TLS option set is small by design

Advanced TLS options can require new typed additions in the future.

Check the current public API in the [API reference](/reference/) before you use Gun options directly.
