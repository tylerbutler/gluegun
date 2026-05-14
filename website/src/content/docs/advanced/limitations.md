---
title: Limitations
description: Know the current boundaries of Gluegun.
---

## Erlang target only

Gluegun wraps Erlang Gun and is not available on the JavaScript target.

## Connection ownership matters

Gun process ownership matters. Requests and WebSocket frames are asynchronous messages sent to the process that owns or awaits the Gun stream unless request options redirect replies.

## High-level client helpers collect bodies in memory

Use low-level `request` and `message` APIs for streaming or advanced Gun flows. The `client` helpers are for regular HTTP responses that can be collected in memory.

## WebSocket over HTTP/2 is unsupported

Gun supports WebSocket over HTTP/1.1. Gluegun rejects HTTP/2 in `websocket.upgrade_with_protocol` by checking the protocol returned from `connection.await_up` before calling Gun.

## TLS option surface is intentionally small

Advanced TLS options may require future typed additions.

Use the [HexDocs API reference](https://hexdocs.pm/gluegun/) to check the current public surface before reaching for Gun options directly.
