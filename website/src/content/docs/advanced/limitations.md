---
title: Limitations
description: Know the current boundaries of Gluegun.
---

Most of the limits of Gluegun come from Gun. Gluegun keeps the Gun process
and message model visible instead of hiding it, so the rules of that model
are also your rules. This page starts with the runtime, then follows a
connection through its processes, its streams, and the data that it returns.

## Erlang target only

Gluegun is an interface to Erlang Gun, so it is not available on the
JavaScript target.

## Connection ownership is important

On the BEAM, each Gun connection is a process, and it belongs to the process
that opened it. Gun monitors the process that calls `connection.open` and
stops the connection when that process exits. Passing the handle does not
transfer ownership, and Gluegun has no owner transfer API. Keep the opener
alive for the connection's lifetime.

Ownership also decides who receives messages. Only the owner receives
connection lifecycle messages such as `gun_up` and `gun_down`, so call
`connection.await_up` there. A different process can time out or observe
connection process exit, but cannot receive readiness. HTTP stream replies go
to the request caller. `websocket.with_reply_to` redirects upgrade and frame
messages, but not connection lifecycle messages. Thus a non-owner WebSocket
receiver can get a close error even after the peer completes the close
handshake.

The high-level `client` functions follow the same rule. They read stream
messages on the calling process during `send`, then return. They do not start
a separate consumer process. See
[process ownership and reply routing](/advanced/message-flow/#process-ownership-and-reply_to).

## Cleanup affects the whole mailbox

Because messages arrive in the caller's mailbox, cleanup removes them from
there. `request.flush` and `connection.terminate` remove queued Erlang `DOWN`
messages for all the caller's monitor references to the connection,
including application monitors. The notifications are not preserved for
separate lifecycle handling. Other processes' mailboxes are unchanged. See
[flush and monitor notifications](/advanced/message-flow/#flush-and-monitor-notifications).

The three ways to stop a connection clean up different amounts.
`connection.close` stops a connection through Gun's supervisor. It waits for
process exit, but does not drain HTTP streams or flush your mailbox.
`connection.shutdown` requests graceful shutdown without waiting, and it
cannot interrupt blocked setup. Only `connection.terminate` suits deadline
cleanup: it forces exit, waits, then flushes the caller's Gun messages. See
[Message Flow](/advanced/message-flow/#close-and-shutdown).

## High-level client functions collect bodies in memory

Inside a connection, the first choice is how much of each response to hold.
The `client` functions collect the full HTTP response in memory. For streams
or advanced Gun flows, use the low-level `request` and `message` APIs.

## Flow credit is not a byte limit

Streaming with the low-level APIs does not give a strict memory limit by
itself. Finite initial flow credit counts data messages. Gun and OTP can
allocate socket buffers or parse several frames before flow control pauses
reads or window updates. Check actual bytes before you retain data, and do
not treat credit as a strict memory cap. See
[Streaming](/guides/streaming/#finite-response-credit).

## HTTP/1.1 cancellation with exhausted flow credit

Finite credit also has one known failure on HTTP/1.1. Gun can leave socket
reads paused when you cancel an HTTP/1.1 response after finite credit runs
out. A later request can time out even after the server sends its response.
Terminate and replace the connection in this case; do not rely on connection
reuse. Termination also discards its other requests. HTTP/2 cancellation does
not have this limitation.

Maintainers accepted this upstream limitation for 1.0. Track it in
[Gluegun #78](https://github.com/tylerbutler/gluegun/issues/78). Related
upstream [ninenines/gun#56](https://github.com/ninenines/gun/issues/56)
discusses cancellation and reconnecting, but does not track this exact
flow-credit stall.

## Fixed-length streamed uploads

Uploads have a Gun limit too. `request.start_stream` rejects `Content-Length`
before it sends headers, because supported Gun versions can crash on some
fixed-length chunk sequences. Use chunked uploads, or send a complete body
with `request.request` or `client`.

## WebSocket over HTTP/2 is not supported

Gun supports WebSocket over HTTP/1.1 only. `websocket.upgrade` checks the
protocol that `connection.await_up` returns, and it rejects HTTP/2 before it
calls Gun.

## Standard HTTP interoperability

The data that a connection returns uses standard Gleam HTTP types where they
fit. HTTP methods use `gleam/http.Method`. Collected responses contain a
standard `gleam/http/response.Response(BitArray)` plus trailers and
informational responses. Keep the outer value to preserve that metadata when
you use standard response helpers.

Requests are different, because they remain path-based and connection-bound.
Gluegun does not accept standard request records or provide converters. The
connection determines the scheme, host, and port, and request helpers accept
the encoded path and query.

Some concepts have no standard type. Connection and stream handles identify
Gun resources. Stream messages, flow-control options, timeout validation, TLS
options, and WebSocket lifecycle types represent behavior outside the standard
HTTP records, so these types remain Gun-specific.

## Numeric options and incoming strings

Gluegun validates values in both directions. Numeric builders return
`InvalidOptions` for invalid values instead of clamping. Finite timeouts
accept 0 through 4_294_967_295 milliseconds, inclusive, as supported by
OTP 27. Use `connection.infinity()` for no limit. Retry counts must be
non-negative; flow credit must be positive; TLS depth accepts 0 through 255;
ports accept 0 through 65535. `connection.milliseconds(5000)` uses `Result`
even for literals so configuration values follow the same validation rule.

Incoming headers have the opposite problem. HTTP header values can contain
bytes that are not UTF-8. Gluegun's `Header` uses strings, so it returns
`DecodeError` for these responses instead of exposing an invalid Gleam string
or changing the bytes.

## The TLS option set is small by design

The typed TLS options cover a small set, so advanced TLS options
can require new typed additions in the future. Check the current public API in
the [API reference](/reference/) before you use Gun options directly.
