---
title: Troubleshooting
description: Common Gluegun issues and where to look first.
---

## Connection never becomes ready

Check the host, port, transport, and timeout passed to `connection.open` and `connection.await_up`. Use `connection.with_transport(transport: connection.Tls)` for port 443 and `connection.with_transport(transport: connection.Tcp)` for port 80 unless the server expects something different.

## WebSocket upgrade fails

WebSocket support is HTTP/1.1 only. Use the default WebSocket options or make sure the negotiated protocol is `Http1` before using low-level upgrade helpers.

## Request fails with an unexpected path or host issue

Gluegun does not parse full URLs. Open the connection with the host and port, then pass only a path such as `/`, `/api/items`, or `/ws` to HTTP and WebSocket helpers.

## High-level client receives an unexpected message

Use `gluegun/client` only for regular HTTP responses that can be collected in memory. Use `gluegun/request`, `gluegun/message`, or `gluegun/websocket` for streaming bodies, trailers as they arrive, HTTP/2 push, upgrades, and WebSocket frames.

## WebSocket receive fails right after upgrade

When using low-level WebSocket helpers, call `websocket.await_upgrade(conn, stream, timeout)` before `websocket.receive(conn, stream, timeout)`. The upgrade acknowledgement is not an application frame.

## WebSocket connection stays open

`websocket.close(socket)` sends a close frame but does not close the underlying Gun connection. Use `websocket.with_socket` for scoped cleanup or call `connection.close` when you own the reusable socket connection lifecycle.

## Response body is not UTF-8

`response.body_text` returns an error when the collected body is not valid UTF-8. Use the raw binary body when the server returns binary data.

## Streaming response does not finish

Continue awaiting messages for the same stream until you receive a final response/data/trailers state. For regular responses, prefer the `client` helpers unless you need chunk-level control.

## Unexpected Erlang error

Gluegun normalizes known Gun and Erlang failures into `GluegunError` values. If you receive an unexpected error, keep the formatted reason in logs and check whether the underlying Gun option or protocol event needs a new typed wrapper.

For complete function-level details, check the [HexDocs API reference](https://hexdocs.pm/gluegun/).
