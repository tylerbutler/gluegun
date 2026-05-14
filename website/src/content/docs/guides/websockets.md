---
title: WebSockets
description: Open, use, and close WebSocket connections with gluegun.
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
