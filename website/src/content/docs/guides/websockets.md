---
title: WebSockets
description: Open, use, and close WebSocket connections with Gluegun.
---

Gun supports WebSocket over HTTP/1.1 only. The high-level WebSocket options in Gluegun use HTTP/1.1 by default. The low-level upgrade functions reject HTTP/2 before they call Gun.

:::caution[HTTP/2 not supported]
Gun does not support WebSocket over HTTP/2 (RFC 8441). `websocket.connect`, `websocket.with_socket`, and `websocket.upgrade_with_protocol` return `UnsupportedFeature` when the negotiated protocol is `Http2`. Set `connection.with_protocols` to `[Http1]` (the default for `websocket.options()`), or check the protocol that `connection.await_up` returns before you upgrade.
:::

Use the reusable `Socket` API when you control the lifecycle yourself.

```gleam
import gleam/io
import gleam/result
import gluegun/error
import gluegun/message
import gluegun/websocket

pub fn ws_echo() {
  use socket <- result.try(
    websocket.connect(
      host: "localhost",
      port: 8080,
      path: "/echo",
      options: websocket.options(),
    ),
  )

  let exchange = {
    use _ <- result.try(websocket.send_text(socket, "hello"))
    case websocket.receive_app_frame(socket) {
      Ok(message.Text(reply)) -> {
        io.println(reply)
        Ok(Nil)
      }
      Ok(_) -> Error(error.InvalidMessage("expected a text frame"))
      Error(error) -> Error(error)
    }
  }

  let cleanup = websocket.close(socket)
  use _ <- result.try(exchange)
  cleanup
}
```

Call `websocket.close(socket)` even after an exchange fails. It sends a close frame, waits for the peer, then terminates the Gun process and flushes this receiver's queued Gun messages. Use the root alias `gluegun.websocket_close` if you use the facade.

The handshake uses one deadline: the socket's finite timeout, or five seconds for `Infinity`. Incoming frames do not extend it. If the peer does not complete the handshake, close returns `Error(Timeout)` after teardown. Connection and stream failures also trigger teardown and return typed errors. A handshake error takes precedence over a termination error. An already-exited connection returns `Ok(Nil)`, so repeated close is safe.

Call from the socket's receiver. If upgrade options redirect frames to another process or an external forwarder, drain that receiver separately. Do not reuse the socket after close.

`websocket.send_close_frame(socket)` only sends a close frame. It does not release the Gun process. Use `websocket.close` for reusable sockets or `websocket.with_socket` for scoped cleanup.

## Scoped sockets

For short one-shot flows, `with_socket` opens the socket, runs a callback, then closes the WebSocket and the connection.

```gleam
import gleam/io
import gleam/result
import gluegun/error
import gluegun/message
import gluegun/websocket

pub fn echo_once() {
  use frame <- result.try(
    websocket.with_socket(
      host: "localhost",
      port: 8080,
      path: "/echo",
      options: websocket.options(),
      callback: fn(socket) {
        use _ <- result.try(websocket.send_text(socket, "hello"))
        websocket.receive_app_frame(socket)
      },
    ),
  )

  case frame {
    message.Text(reply) -> {
      io.println(reply)
      Ok(Nil)
    }
    _ -> Error(error.InvalidMessage("expected a text frame"))
  }
}
```

`with_socket` calls `websocket.close` after the callback returns, including when it returns an error. Callback errors take precedence over cleanup errors. If the callback succeeds, a teardown error becomes the result of `with_socket`. A callback can close its own socket; the later scoped close remains safe.

## Low-level upgrade flow

Use the low-level functions when you already control the connection lifecycle, or when you must check the negotiated protocol before the upgrade.

```gleam
import gleam/result
import gluegun/connection
import gluegun/error
import gluegun/message
import gluegun/websocket

pub fn low_level_echo(conn) {
  use timeout <- result.try(connection.milliseconds(5000))
  use protocol <- result.try(connection.await_up(conn, timeout))

  use stream <- result.try(
    websocket.upgrade_with_protocol(conn, protocol, "/echo", []),
  )

  use _ <- result.try(websocket.await_upgrade(conn, stream, timeout))
  use _ <- result.try(websocket.send(conn, stream, message.Text("hello")))

  case websocket.receive(conn, stream, timeout) {
    Ok(message.Text(reply)) -> Ok(reply)
    Ok(_) -> Error(error.InvalidMessage("received a non-text frame"))
    Error(err) -> Error(err)
  }
}
```

Call `websocket.await_upgrade` before `websocket.receive`. If you do not, the upgrade acknowledgement can arrive where your code waits for a WebSocket frame.

See the [WebSocket reference](/reference/gluegun-websocket/) for upgrade options, low-level functions, and reusable socket functions.
