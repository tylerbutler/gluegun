---
title: WebSockets
description: Open, use, and close WebSocket connections with Gluegun.
---

Gluegun gives you three ways to use a WebSocket. A reusable `Socket` lets you
control its lifecycle. `with_socket` opens, uses, and closes a socket in one
call. The low-level upgrade flow adopts a connection that you already opened.
All three share one rule from Gun: WebSockets run over HTTP/1.1 only.

`websocket.connect` forces HTTP/1.1
and zero retries after applying your connection options, including TLS
settings. A dropped socket returns `ConnectionDown`. Reconnecting Gun as HTTP
would not restore its WebSocket upgrade.

The high-level functions also fix where messages go. `connect` and `with_socket` await the handshake in the calling process.
They accept an absent `reply_to` or the caller's PID. A different PID returns
`InvalidOptions` before opening a connection, even with an `Infinity` timeout.
To receive in another process, use the low-level upgrade flow below.

:::caution[HTTP/2 not supported]
Gun does not support WebSocket over HTTP/2 (RFC 8441).
`websocket.upgrade(conn, protocol, path, headers, options)` rejects `Http2`
before calling Gun. The high-level `connect` and `with_socket` select HTTP/1.1.
:::

## Reusable sockets

Use the reusable `Socket` API when you control the lifecycle yourself. The
example creates its cleanup before it examines the result of the exchange:

For frames and application commands in one process loop, see
[OTP Actors](/guides/actors/). Use `message.select` and record each delivered
envelope through `websocket.record_frame` before handling or closing.

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

That cleanup is easy to forget. For short one-shot flows, use `with_socket` to handle it for you. It opens
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

Both reusable and scoped sockets use `websocket.close` for teardown, so they
close in the same way. The close
handshake uses one deadline: the socket's finite timeout, or five seconds for
`Infinity`. Incoming frames do not extend it. If the peer does not complete the
handshake, close returns `Error(Timeout)` after teardown. Connection and stream
failures also trigger teardown and return typed errors. A handshake error takes
precedence over a termination error. An already-exited connection returns
`Ok(Nil)`, so repeated close is safe.

Process teardown first attempts supervisor shutdown for up to 100 milliseconds.
If the stop fails or exceeds that allowance, it sends a kill signal. This avoids
a supervisor error report for a successful stop. The stop allowance is separate
from the handshake deadline; waiting for process exit and mailbox cleanup can
add time. Close returns only after the Gun process has exited and this
receiver's queued Gun messages have been flushed.

Call `websocket.close` from the socket's receiver. If upgrade options redirect
frames to another process or an external forwarder, drain that receiver
separately. Do not reuse the socket after close.

The receiver and the owner are not always the same process. The connection owner is the process that opened it. Gun monitors that process
and stops the connection when it exits. Passing a `Socket` or using
`with_reply_to` does not transfer ownership. Only the owner receives `gun_up`
and `gun_down`; `with_reply_to` redirects upgrade and frame messages.

If the socket's receiver is not the owner, close can return `Timeout` or
`ConnectionDown` even after a successful peer close handshake, because the
normal `gun_down` confirmation goes to the owner. Prefer opening and receiving
in the same process. Teardown also removes queued Erlang `DOWN` notifications
for all the caller's monitors of that connection. See
[Message Flow](/advanced/message-flow/#flush-and-monitor-notifications).

Do not confuse `websocket.close` with `websocket.send_close_frame(socket)`, which only sends a close frame. It does not
release the Gun process. Use `websocket.close` for reusable sockets or
`websocket.with_socket` for scoped cleanup.

## Control frames

Between the open and the close, the peer can send control frames as well as application data. Gun automatically sends one matching pong for each incoming ping. The
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

When you send control frames yourself, Gluegun checks them against the protocol limits. You can send up to 125 bytes in a Ping or Pong payload. A `CloseWithReason`
reason must contain valid UTF-8 and at most 123 bytes. The close code uses two
more bytes. Gluegun accepts close codes 1000-1003, 1007-1014, and 3000-4999.
Use `Close` to send a close frame without a code or reason.

Invalid control frames return `InvalidMessage` before Gluegun calls Gun.
`send_many` checks the complete list before sending any frame. After a rejected
send, you can continue to use the connection.

In a `send_many` batch, `Close` or `CloseWithReason` must be last. If any frame
follows a close frame, Gluegun returns `InvalidMessage` and sends no frames.

## Low-level upgrade flow

The high-level functions open their own connection. Use the low-level functions when you already control the connection lifecycle, or when you must check the negotiated protocol before the upgrade.

WebSocket upgrades have no request body. A positive `Content-Length` returns
`InvalidOptions` before Gluegun calls Gun. Omit this header or use zero.
Remove a positive length when you reuse headers from an HTTP request with a body.
Ordinary HTTP requests with bodies still accept a positive length.

The process that calls this example must also have opened `conn`, so it can
receive readiness through `connection.await_up`.

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

For delegated reception, the owner calls `upgrade` with
`websocket.with_reply_to(options, receiver)`. Pass the connection and returned
stream to that receiver. The receiver calls `await_upgrade` and `from_upgrade`,
then sends and receives frames. Keep the owner alive throughout the session;
delegation does not transfer ownership or redirect `gun_up` and `gun_down`.

## Automatic keepalive pings

Gun sends no automatic pings by default (`infinity()`). For `connect` and
`with_socket`, set the interval through high-level upgrade options:

```gleam
let assert Ok(interval) = connection.milliseconds(30_000)
let options =
  websocket.options()
  |> websocket.with_upgrade_options(
    websocket.upgrade_options() |> websocket.with_keepalive(interval),
  )
```

The helpers apply this value when opening the connection, where Gun reads its
WebSocket timer. An explicit upgrade setting takes precedence over
`connection.with_websocket_keepalive`, regardless of builder order. If absent,
the connection setting or Gun's default is preserved. Use `infinity()` to
disable pings explicitly. Keepalive does not change connection readiness,
upgrade, or frame receive timeouts; set those with `websocket.with_timeout`.

For a low-level upgrade, configure the interval before opening:

```gleam
let assert Ok(interval) = connection.milliseconds(30_000)
let options =
  connection.options()
  |> connection.with_websocket_keepalive(interval)
```

Pass these connection options to `connection.open`, then use
`websocket.upgrade_options()` for the upgrade. A direct `websocket.upgrade`
with `websocket.with_keepalive` returns `InvalidOptions` before sending,
even for `infinity()`. Move that setting to
`connection.with_websocket_keepalive`: Gun does not apply upgrade-only
keepalive values to its connection timer.

## Subprotocols

A server can offer more than one application protocol on the same path. Use `websocket.with_subprotocols(options, ["chat", "graphql-transport-ws"])`
to request subprotocols with Gun's default handler. You do not need an Erlang
module name. Names must be non-empty ASCII HTTP tokens and must be unique.
Gluegun rejects the complete list with `InvalidOptions` before sending anything
if a name is invalid or repeated. Order and case are preserved; `"chat"` and
`"Chat"` are distinct names.

Read `websocket.selected_subprotocol(socket)` after connect or adoption to
find the server's selection. The handshake also retains other response
headers. Custom Erlang handler modules and proxy tunnels remain internal.

See the [WebSocket reference](/reference/gluegun-websocket/) for upgrade options, low-level functions, and reusable socket functions.
