---
title: WebSockets
description: Open, use, and close WebSocket connections with Gluegun.
---

Gun supports WebSocket over HTTP/1.1 only. Gluegun's high-level WebSocket options default to HTTP/1.1, and low-level upgrade helpers reject HTTP/2 before calling Gun.

Use the reusable `Socket` API when you want explicit lifecycle control.

```gleam
import gleam/io
import gluegun/message
import gluegun/websocket

pub fn echo() {
  let assert Ok(socket) =
    websocket.connect(
      host: "localhost",
      port: 8080,
      path: "/echo",
      options: websocket.options(),
    )

  let assert Ok(Nil) = websocket.send_text(socket, "hello")

  case websocket.receive_app_frame(socket) {
    Ok(message.Text(reply)) -> io.println(reply)
    Ok(_) -> io.println("received a non-text frame")
    Error(_) -> io.println("websocket receive failed")
  }

  let assert Ok(Nil) = websocket.close(socket)
}
```

`websocket.close(socket)` sends a WebSocket close frame. It does not close the underlying Gun connection. Use `websocket.with_socket` for scoped cleanup, or close the connection yourself when using the reusable `Socket` API.

## Scoped sockets

For shorter one-shot flows, `with_socket` opens the socket, runs a callback, then closes the WebSocket and connection.

```gleam
import gleam/io
import gluegun/message
import gluegun/websocket

pub fn echo_once() {
  let assert Ok(message.Text(reply)) =
    websocket.with_socket(
      host: "localhost",
      port: 8080,
      path: "/echo",
      options: websocket.options(),
      callback: fn(socket) {
        let assert Ok(Nil) = websocket.send_text(socket, "hello")
        websocket.receive_app_frame(socket)
      },
    )

  io.println(reply)
}
```

`Socket` is reusable and lifecycle-explicit. `with_socket` is convenience-only for scoped use.

## Low-level upgrade flow

Use the low-level helpers when you already own the connection lifecycle or need to inspect the negotiated protocol before upgrading.

```gleam
import gluegun/connection
import gluegun/message
import gluegun/websocket

pub fn low_level_echo(conn) {
  let timeout = connection.Milliseconds(5000)
  let assert Ok(protocol) = connection.await_up(conn, timeout)

  let assert Ok(stream) =
    websocket.upgrade_with_protocol(conn, protocol, "/echo", [])

  let assert Ok(Nil) = websocket.await_upgrade(conn, stream, timeout)
  let assert Ok(Nil) = websocket.send(conn, stream, message.Text("hello"))

  case websocket.receive(conn, stream, timeout) {
    Ok(message.Text(reply)) -> Ok(reply)
    Ok(_) -> Error("received a non-text frame")
    Error(_) -> Error("websocket receive failed")
  }
}
```

Call `websocket.await_upgrade` before `websocket.receive`; otherwise the upgrade acknowledgement may arrive where a WebSocket frame is expected.

See the [WebSocket module on HexDocs](https://hexdocs.pm/gluegun/gluegun/websocket.html) for upgrade options, low-level helpers, and reusable socket helpers.
