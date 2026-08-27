---
title: Troubleshooting
description: Common Gluegun problems and where to look first.
---

## Connection does not become ready

Check the host, port, transport, and timeout given to `connection.open` and `connection.await_up`. Use `connection.with_transport(transport: connection.Tls)` for port 443. Use `connection.with_transport(transport: connection.Tcp)` for port 80. Use a different transport only when the server requires it.

## WebSocket upgrade fails

WebSocket works only on HTTP/1.1. Use the default WebSocket options. Or, before you use the low-level upgrade functions, make sure that the negotiated protocol is `Http1`.

## Request fails with an unexpected path or host problem

Gluegun does not parse full URLs. Open the connection with the host and port. Then give only a path such as `/`, `/api/items`, or `/ws` to the HTTP and WebSocket functions. If your caller supplies full URLs, first parse them with `gleam/uri`. Then give the parsed host, port, path, and query to Gluegun.

## High-level client gets an unexpected message

Use `gluegun/client` only for usual HTTP responses that can be collected in memory. The client functions reject HTTP/2 server push, protocol upgrades, and WebSocket frames with `InvalidMessage`. Use `gluegun/request`, `gluegun/message`, or `gluegun/websocket` for streamed bodies, trailers as they arrive, HTTP/2 push, upgrades, and WebSocket frames.

## WebSocket receive fails immediately after upgrade

With the low-level WebSocket functions, call `websocket.await_upgrade(conn, stream, timeout)` before `websocket.receive(conn, stream, timeout)`. The upgrade acknowledgement is not an application frame.

## WebSocket connection stays open

`websocket.send_close_frame(socket)` sends a close frame. It does not close the Gun connection below it. Do one of these:

- Use `websocket.with_socket(...)` for scoped cleanup. It sends the close frame and calls `connection.close` for you.
- When you hold the reusable `Socket` yourself, call `connection.close(socket.connection)` after `send_close_frame`. This releases the TCP/TLS connection.

## Response body is not UTF-8

`response.body_text` returns an error when the collected body is not valid UTF-8. Use the raw binary body when the server returns binary data.

## Streamed response does not complete

Continue to wait for messages on the same stream until you get a final response, data, or trailers state. For usual responses, use the `client` functions unless you must control each chunk.

## Unexpected Erlang error

Gluegun normalizes known Gun and Erlang failures into `GluegunError` values. If you get an unexpected error, keep the formatted reason in the logs. Then check if the Gun option or protocol event requires a new typed wrapper.

For full function-level details, see the [API reference](/reference/).
