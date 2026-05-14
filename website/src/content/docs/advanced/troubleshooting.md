---
title: Troubleshooting
description: Common gluegun issues and where to look first.
---

## Connection never becomes ready

Check the host, port, transport, and timeout passed to `connection.open` and `connection.await_up`. Use TLS for port 443 and plaintext TCP for port 80 unless the server expects something different.

## WebSocket upgrade fails

WebSocket support is HTTP/1.1 only. Use the default WebSocket options or make sure the negotiated protocol is `Http1` before using low-level upgrade helpers.

## Response body is not UTF-8

`response.body_text` returns an error when the collected body is not valid UTF-8. Use the raw binary body when the server returns binary data.

## Streaming response does not finish

Continue awaiting messages for the same stream until you receive a final response/data/trailers state. For regular responses, prefer the `client` helpers unless you need chunk-level control.

## Unexpected Erlang error

Gluegun normalizes known Gun and Erlang failures into `GluegunError` values. If you receive an unexpected error, keep the formatted reason in logs and check whether the underlying Gun option or protocol event needs a new typed wrapper.
