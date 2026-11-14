---
title: WebSockets
description: Open, use, and close WebSocket connections with Gluegun.
---

Gun supports WebSocket over HTTP/1.1 only. `websocket.connect` forces HTTP/1.1
and zero retries after applying your connection options, including TLS
settings. A dropped socket returns `ConnectionDown`. Reconnecting Gun as HTTP
would not restore its WebSocket upgrade.

:::caution[HTTP/2 not supported]
Gun does not support WebSocket over HTTP/2 (RFC 8441).
`websocket.upgrade(conn, protocol, path, headers, options)` rejects `Http2`
before calling Gun. The high-level `connect` and `with_socket` select HTTP/1.1.
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

Call `websocket.close(socket)` even after an exchange fails. It sends a close frame, waits for the peer, then terminates the Gun process and flushes this receiver's queued Gun messages.

## Scoped sockets

For short one-shot flows, use `with_socket` to handle cleanup for you. It opens
the socket, runs a callback, then closes the WebSocket and the connection.

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

If the callback panics, fails an assertion, or raises an Erlang exception,
`with_socket` performs the same teardown with a finite close deadline, then
re-raises the original exception with its class, reason, and stack. Cleanup
errors cannot replace the callback exception. This also releases the socket when you catch the exception
outside `with_socket` and keep the owner process alive.

## Close behavior

Both reusable and scoped sockets use `websocket.close` for teardown. The close
handshake uses one deadline: the socket's finite timeout, or five seconds for
`Infinity`. Incoming frames do not extend it. If the peer does not complete the
handshake, close returns `Error(Timeout)` after teardown. Connection and stream
failures also trigger teardown and return typed errors. A handshake error takes
precedence over a termination error. An already-exited connection returns
`Ok(Nil)`, so repeated close is safe.

Call `websocket.close` from the socket's receiver. If upgrade options redirect
frames to another process or an external forwarder, drain that receiver
separately. Do not reuse the socket after close.

`websocket.send_close_frame(socket)` only sends a close frame. It does not
release the Gun process. Use `websocket.close` for reusable sockets or
`websocket.with_socket` for scoped cleanup.

## Control frames

Gun automatically sends one matching pong for each incoming ping. The
`silence_pings` upgrade option controls whether ping and pong frames reach the
receiver; it does not disable automatic replies. `receive_app_frame` skips
visible ping and pong frames, including empty payloads, and returns the next
text, binary, or close frame. It does not send another pong. Use
`websocket.pong` when you need to send an explicit pong.

Each `receive_app_frame` call uses one total deadline from the socket's
configured timeout. Skipped control frames do not restart the deadline.
`Infinity` permits an unlimited wait. A zero timeout returns `Error(Timeout)`
without consuming queued frames. `receive_frame` waits for one frame using
the socket's timeout.

You can send up to 125 bytes in a Ping or Pong payload. A `CloseWithReason`
reason must contain valid UTF-8 and at most 123 bytes. The close code uses two
more bytes. Gluegun accepts close codes 1000-1003, 1007-1014, and 3000-4999.
Use `Close` to send a close frame without a code or reason.

Invalid control frames return `InvalidMessage` before Gluegun calls Gun.
`send_many` checks the complete list before sending any frame. After a rejected
send, you can continue to use the connection.

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
    websocket.upgrade(conn, protocol, "/echo", [], websocket.upgrade_options()),
  )

  use handshake <- result.try(websocket.await_upgrade(conn, stream, timeout))
  let socket = websocket.from_upgrade(conn, stream, handshake, timeout)
  let exchange = {
    use _ <- result.try(websocket.send_text(socket, "hello"))
    websocket.receive_frame(socket)
  }
  let cleanup = websocket.close(socket)
  use frame <- result.try(exchange)
  use _ <- result.try(cleanup)

  case frame {
    message.Text(reply) -> Ok(reply)
    _ -> Error(error.InvalidMessage("received a non-text frame"))
  }
}
```

`await_upgrade` consumes informational responses until the upgrade completes
under one deadline. Its handshake result retains the response headers.
Adopt it before reading application frames, then use the Socket operations
for send, receive, and close with a finite deadline.

## Subprotocols

Use `websocket.with_subprotocols(options, ["chat", "graphql-transport-ws"])`
to request subprotocols with Gun's default handler. You do not need an Erlang
module name. Names must be non-empty ASCII HTTP tokens; Gluegun rejects the
complete list before sending anything if a name is invalid.

Read `websocket.selected_subprotocol(socket)` after connect or adoption to
find the server's selection. The handshake also retains other response
headers. Custom Erlang handler modules and proxy tunnels remain internal.

See the [WebSocket reference](/reference/gluegun-websocket/) for upgrade options, low-level functions, and reusable socket functions.
