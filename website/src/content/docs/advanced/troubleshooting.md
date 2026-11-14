---
title: Troubleshooting
description: Common Gluegun problems and where to look first.
---

## Connection does not become ready

Call `connection.await_up` in the process that opened the connection.
Only that owner receives `gun_up`. A different process can return `Timeout`
while the connection stays alive, or `ConnectionDown` if it exits during
the wait. Passing the handle does not transfer ownership.

Check the host, port, transport, and timeout given to `connection.open` and `connection.await_up`. Use `connection.with_transport(transport: connection.Tls)` for port 443. Use `connection.with_transport(transport: connection.Tcp)` for port 80. Use a different transport only when the server requires it.

## Connection stops after a task returns

Gun monitors the process that opened the connection and stops it when the
opener exits. Open the connection in a process that stays alive for its
full lifetime. Returning the handle from a short-lived task does not
transfer ownership to the recipient.

## WebSocket upgrade fails

WebSocket works only on HTTP/1.1. Use the default WebSocket options. Or, before you use the low-level upgrade functions, make sure that the negotiated protocol is `Http1`.

## Request fails with an unexpected path or host problem

Gluegun does not parse full URLs. Open the connection with the host and port. Then give only a path such as `/`, `/api/items`, or `/ws` to the HTTP and WebSocket functions. If your caller supplies full URLs, first parse them with `gleam/uri`. Then give the parsed host, port, path, and query to Gluegun.

## High-level client gets an unexpected message

Use `gluegun/client` only for HTTP responses that you can collect in memory. The client functions reject HTTP/2 server push, protocol upgrades, and WebSocket frames with `InvalidMessage`. Use `gluegun/request`, `gluegun/message`, or `gluegun/websocket` for streamed bodies, trailers as they arrive, HTTP/2 push, upgrades, and WebSocket frames.

## WebSocket receive fails immediately after upgrade

With an existing connection, call `websocket.await_upgrade(conn, stream, timeout)`
and adopt its handshake with `websocket.from_upgrade` before using
`websocket.receive_frame(socket)`. The upgrade acknowledgement is not an
application frame.

## WebSocket connection stays open

`websocket.send_close_frame(socket)` sends a close frame. It does not close the Gun connection below it. Do one of these:

- Use `websocket.with_socket(...)` for scoped cleanup.
- When you hold a reusable `Socket`, call `websocket.close(socket)`, including after a failed exchange.

Both paths wait for the peer within the socket timeout, or five seconds for
`Infinity`. Process cleanup then attempts supervisor shutdown for up to 100
milliseconds before killing on failure or expiry. This allowance is separate
from the handshake deadline; waiting for process exit and flushing this
receiver's queued messages can add time. A missing close reply returns `Timeout`
after cleanup. Other handshake failures return typed errors after cleanup.
Repeated close succeeds after the process exits.

## WebSocket close fails after the peer handshake succeeds

Check whether the socket receiver also opened the connection.
`websocket.with_reply_to` redirects upgrade and frame messages but not
`gun_down`, which goes only to the connection owner. A non-owner receiver
can return `Timeout` or `ConnectionDown` after a successful peer close
handshake. Prefer opening and receiving in the same process.

## Application monitor notification is missing

`request.flush` and `connection.terminate` call `gun:flush`, which removes
queued Erlang `DOWN` messages for every caller monitor reference to the
connection. This includes your application's monitors. `websocket.close`
uses the same termination cleanup. Do not wait for those discarded
notifications. See [Message Flow](/advanced/message-flow/#flush-and-monitor-notifications).

## Response body is not UTF-8

`response.body_text` returns an error when the collected body is not valid UTF-8. Use the raw binary body when the server returns binary data.

## Streamed response does not complete

Continue to wait for messages on the same stream until you get a final response, data, or trailers state. If the full response fits in memory and you do not need to control each chunk, use the `client` functions.

## Unexpected Erlang error

Gluegun normalizes known Gun and Erlang failures into `GluegunError` values. If you get an unexpected error, keep the formatted reason in the logs. Then check if the Gun option or protocol event requires a new typed wrapper.

For full function-level details, see the [API reference](/reference/).
