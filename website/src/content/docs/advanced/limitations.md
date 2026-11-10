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

## HTTP/1.1 cancellation with exhausted flow credit

Gun can leave socket reads paused when you cancel an HTTP/1.1 response after
finite credit runs out. A later request can time out even after the server
sends its response. Terminate and replace the connection in this case; do not
rely on connection reuse. Termination also discards its other requests.

Maintainers accepted this upstream limitation for 1.0. Track it in
[Gluegun #78](https://github.com/tylerbutler/gluegun/issues/78). Related upstream
[ninenines/gun#56](https://github.com/ninenines/gun/issues/56) discusses
cancellation and reconnecting, but does not track this exact flow-credit stall.
HTTP/2 cancellation does not have this limitation.

## Fixed-length streamed uploads

`request.start_stream` rejects `Content-Length` before sending headers.
Supported Gun versions can crash on some fixed-length chunk sequences. Use
chunked uploads, or send a complete body with `request.request` or `client`.

## Numeric options and incoming strings

Numeric builders return `InvalidOptions` for invalid values instead of
clamping. Timeouts and retry counts must be non-negative; flow credit must be
positive; TLS depth accepts 0 through 255; ports accept 0 through 65535.
`connection.milliseconds(5000)` uses `Result` even for literals so configuration
values follow the same validation rule.

HTTP header values can contain bytes that are not UTF-8. Gluegun's `Header`
uses strings, so it returns `DecodeError` for these responses rather than
exposing an invalid Gleam string or changing the bytes.

## WebSocket over HTTP/2 is not supported

Gun supports WebSocket over HTTP/1.1. `websocket.upgrade` checks the protocol that `connection.await_up` returns. It rejects HTTP/2 before it calls Gun.

## The TLS option set is small by design

Advanced TLS options can require new typed additions in the future.

Check the current public API in the [API reference](/reference/) before you use Gun options directly.
