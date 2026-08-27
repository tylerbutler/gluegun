---
title: Limitations
description: Know the current boundaries of Gluegun.
---

## Erlang target only

Gluegun is an interface to Erlang Gun. It is not available on the JavaScript target.

## Connection ownership is important

Gun process ownership is important. Requests and WebSocket frames are asynchronous messages. Gun sends them to the process that owns, or waits for, the Gun stream, unless request options send replies to a different process. The high-level `client` functions read those messages on the calling process during `send`, then return. They do not start a separate consumer process.

## `close` and `shutdown`

Use `connection.close` for usual teardown. Gun sends its shutdown signal and waits for the process to exit. Use `connection.shutdown` only when a connection seems stuck. `shutdown` stops the Gun process immediately, without a graceful close. In both cases, open streams are canceled.

## High-level client functions collect bodies in memory

Use the low-level `request` and `message` APIs for streams or advanced Gun flows. The `client` functions are for usual HTTP responses that can be collected in memory.

## WebSocket over HTTP/2 is not supported

Gun supports WebSocket over HTTP/1.1. `websocket.upgrade_with_protocol` checks the protocol that `connection.await_up` returns. It rejects HTTP/2 before it calls Gun.

## The TLS option set is small by design

Advanced TLS options can require new typed additions in the future.

Check the current public API in the [API reference](/reference/) before you use Gun options directly.
