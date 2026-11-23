---
title: Message Flow
description: Learn the connection lifecycle, stream messages, flow control, and ownership.
---

Gluegun keeps the asynchronous process model of Gun visible. It does not hide the model behind one blocking request API. This is why the lower-level `gluegun/request`, `gluegun/message`, and `gluegun/websocket` modules are useful for streams, push, upgrades, and long-lived connections.

The main flow is:

1. Open a connection with `gluegun/connection`.
2. Wait until the connection is ready with `connection.await_up`.
3. Start a stream with `gluegun/request`, or a WebSocket upgrade with `gluegun/websocket`.
4. Wait for typed `gluegun/message.Message` values for that stream.
5. Decide if you continue the stream, add flow-control allowance, cancel, or close the connection.

The high-level `gluegun/client` functions use this flow to send an HTTP request and collect the full response in memory. To handle protocol messages such as push, upgrades, and WebSocket frames, use the lower-level modules; the client functions reject those messages.

## `message.await` and `message.await_body`

- `message.await(conn, stream, timeout)` returns the *next* message for a stream as a typed `Message`. Use it in a loop to process `Inform`, `Response`, `Data`, `Trailers`, `Push`, `Upgrade`, and `WebSocket` values explicitly. This is the correct option for streams, server push, upgrade flows, or when you apply backpressure.
- `message.await_body(conn, stream, timeout)` collects body chunks until `Data(fin.Fin, ...)` or `Trailers(...)` and returns the bytes as one value. Call it only after you receive `Response(fin.NoFin, ...)` (for example, from a previous `await`). After `Response(fin.Fin, ...)`, the response is complete and there is no body to await. The full body stays in memory. If the response ends with trailers, `await_body` still returns the body, but it discards the trailer headers. Use `await` when you must get the trailers.
- `message.decode(gun_message)` changes a raw Gun mailbox message into a typed `Envelope(connection:, stream:, message:)`. The envelope contains the decoded `Message` and its connection and stream. It accepts the mailbox tuples that Gun sends to the process that owns the stream (`gun_response`, `gun_data`, `gun_inform`, `gun_trailers`, `gun_push`, `gun_upgrade`, `gun_ws`). It rejects the shorter terms that `gun:await/3` returns with `DecodeError`, because those terms have no connection or stream identity. Use `decode` when your own Erlang FFI receives Gun messages outside the Gluegun functions. If your process owns several streams, use the envelope to identify the source of each message. For `Push`, the envelope's `stream` is the existing stream that received the notification. The new stream is inside `message.Push`.

For chunked bodies, see the [streaming guide](/guides/streaming/). For WebSocket upgrade flows, see the [websockets guide](/guides/websockets/).

For mailbox errors, `message.decode` returns `StreamError` for a stream-level `gun_error`, `ConnectionError` for a connection-level `gun_error`, and `ConnectionDown` for `gun_down`. Each error includes Gun's reason string without an envelope. `await` and `await_body` use the same categories and return `ConnectionDown` if the connection process exits. A receive timeout returns `Timeout`.

## Actor and selector reception

Use `message.select(selector, mapping)` to compose Gun reception with your
application subjects. It selects supported Gun mailbox tuples by tag and arity
across all connections in this receiver. Route by the event's connection and
stream handles. It does not select external `DOWN` messages or arbitrary
application messages.

`message.Event` adds source-identified lifecycle and error events alongside
`StreamMessage(Envelope)`. `message.decode_event` exposes the same decoder to
existing Erlang integrations. `Message` and `message.decode` stay unchanged.
For WebSocket envelopes, call `websocket.record_frame` once before handling
the frame, to retain peer-close and finite-credit teardown state.
See [OTP Actors](/guides/actors/) for the complete Gleam-only loop.

## `await_up` and the negotiated protocol

Gun `open/2` returns immediately after it starts the connection process. The socket connect and the protocol negotiation occur asynchronously. `connection.await_up` waits for the Gun `up` message and returns the negotiated `Protocol`.

Call `await_up` in the process that opened the connection. Only that owner
receives `gun_up`. A different process can time out while the connection
stays alive, or get `ConnectionDown` if the connection process exits during
the wait. Holding the handle does not give a process readiness messages.

The returned `Protocol` is the protocol that Gun selected. For TLS connections, this includes the ALPN result. If you do not call `await_up`, later stream messages still queue correctly and the connection can still work. But your code cannot know if Gun negotiated HTTP/1.1 or HTTP/2. This is important for decisions such as `websocket.upgrade`, which rejects `Http2` before it calls Gun.

## `close` and `shutdown`

`connection.close` calls Gun's supervisor to stop the connection process. The supervisor waits for exit, then forces termination after its shutdown timeout (five seconds in Gun 2.1/2.2). This is not an HTTP stream drain. The call does not flush your mailbox.

`connection.shutdown` sends an asynchronous graceful-shutdown request. Gun can finish active streams before it exits. The call does not wait for exit and cannot interrupt a blocked setup stage.

Use `connection.terminate` when a deadline expires or setup stalls. It sends an untrappable kill signal, waits for process exit, then flushes that connection's Gun messages from the calling process. Call it from the receiving process. After it returns, the Gun process cannot send more messages. Other receivers and third-party message forwarders need their own cleanup. Forced termination can produce a Gun supervisor report with reason `killed`.

## `Fin` and `NoFin`: HTTP is half-closed

Inside a stream, each side tells the other when it has finished. Gluegun shows this half-close model of Gun with `gluegun/fin.Fin` and `gluegun/fin.NoFin`.

On the request side, `request.data(conn, stream, fin.NoFin, chunk)` sends more bytes and tells Gun that the request body is not complete. `fin.Fin` on the last chunk tells Gun that there are no more request bytes. This final signal lets many servers start the response.

On the response side, a normal HTTP response starts with zero or more
`message.Inform` messages, then follows one of three sequences:

- `message.Response(fin.Fin, status, headers)` ends a headers-only response.
- `message.Response(fin.NoFin, status, headers)`, zero or more
  `message.Data(fin.NoFin, data)` messages, then
  `message.Data(fin.Fin, data)` deliver a body without trailers.
- `message.Response(fin.NoFin, status, headers)`, zero or more
  `message.Data(fin.NoFin, data)` messages, then `message.Trailers(headers)`
  deliver a response with trailers.

Stop receiving for that response at any of these three terminal events:
`Response(fin.Fin, ...)`, `Data(fin.Fin, ...)`, or `Trailers(...)`.
`fin.NoFin` means that body chunks or trailers follow. With trailers, all
body chunks use `fin.NoFin`; there is no separate `Data(fin.Fin, ...)`.
Do not wait for trailers after `Fin`.

## Cancellation

Sometimes you must stop a stream before it reaches a terminal event. `request.cancel(conn, stream)` sends an asynchronous cancellation for one stream. Queued messages and late arrivals can remain while Gun processes it. The connection stays open for other streams.

`request.flush(conn)` removes only messages queued at that instant. For terminal cleanup, cancel the stream if needed, then call `connection.terminate(conn)` from the receiver. Termination discards all streams on the connection.

### Flush and monitor notifications

Both cleanup calls flush the mailbox, and that flush reaches further than the connection's own stream messages. `request.flush` and `connection.terminate` call `gun:flush` with the connection
handle. The flush removes queued messages for all streams on that connection
in the caller's mailbox. It also removes queued Erlang
`{'DOWN', monitor_ref, process, connection_pid, reason}` messages for every
monitor reference to that connection, including monitors created by your
application. It does not change other processes' mailboxes.

Flushing a live connection does not demonitor it. When the connection exits,
Erlang removes its monitors and sends their `DOWN` notifications. A later
flush can discard those queued notifications. Do not wait for a discarded
`DOWN` after either call.
In particular, `connection.terminate` has already waited for process exit;
its flush can consume the notification your own lifecycle code expected.
`websocket.close` uses the same termination cleanup.

## Flow control

Cancellation stops a stream; flow control only slows it. Set finite credit with `request.with_initial_flow(options, credit)` before `request.request` or `request.start_stream`. Without it, Gun starts with unlimited credit; a later `update_flow` cannot change unlimited credit to finite credit.

With Gun's default data handler, one credit permits one data message in both HTTP/1.1 and HTTP/2. Headers do not consume credit. `request.update_flow(conn, stream, increment)` adds credit in the same unit. HTTP/1.1 pauses socket reads when credit runs out. HTTP/2 stops replenishing the stream's byte window; it can still process frames already in that window or socket read. Credit is not the HTTP/2 byte window and does not impose a strict message-count or memory bound. See the [streaming guide](/guides/streaming/#finite-response-credit) for allocation limits.

## WebSocket frame model

After a WebSocket upgrade, the stream carries frames instead of HTTP messages. `message.WebSocket(frame)` holds typed WebSocket frames. Gluegun keeps text, binary, ping, pong, and close frames as different variants. It does not merge them into one shape.

Gun processes ping and pong automatically by default. `websocket.with_silence_pings` controls if automatic ping processing stays hidden, or if ping frames are visible to your code. `Ping` and `Pong` each hold a payload `BitArray`. An empty payload is valid. It means that no application data was attached.

`message.CloseWithReason(code, reason)` keeps the close reason as raw bytes. RFC 6455 says that the reason payload is UTF-8 text. Gluegun keeps it as a `BitArray`. Thus the caller decides when and how to decode it safely.

## Process ownership and `reply_to`

Each message on this page goes to a process, and the rules for which process explain many surprises. The process that calls `connection.open` is the connection owner. Gun
monitors this process and stops the connection when it exits. Passing a
`Connection` or `Socket` handle to another process does not transfer
ownership. A short-lived task cannot open a connection, return its handle,
and exit while another process continues to use it. Open long-lived
connections in a process that stays alive for their full lifetime.
Gluegun has no owner transfer API.

Gun sends connection lifecycle messages, including `gun_up` and `gun_down`,
only to the connection owner. HTTP stream replies go to the process that
calls `request.request` or `request.start_stream`, which can differ from the
owner. Calling `message.await` in another process does not redirect those
replies.

WebSocket upgrade and frame messages go to the upgrade caller by default.
`websocket.with_reply_to` sends those stream messages to the configured
process instead. It does not change the connection owner or redirect
`gun_up` and `gun_down`.

If the receiving process stops before it processes the messages, those messages are lost. Gluegun does not keep them in a different location.

In this example, `conn` must have been opened by the current process,
because that process calls `await_up`:

```gleam
import gleam/erlang/process
import gluegun/connection
import gluegun/websocket

pub fn upgrade_in_current_process(conn) {
  let options =
    websocket.upgrade_options()
    |> websocket.with_reply_to(receiver: process.self())

  let assert Ok(timeout) = connection.milliseconds(5000)
  let assert Ok(protocol) = connection.await_up(conn, timeout)

  let assert Ok(stream) =
    websocket.upgrade(
      conn,
      protocol,
      "/ws",
      [],
      options,
    )

  stream
}
```

The receiver must await the upgrade and own the Socket receive/close sequence.
If the receiver is not the connection owner, `websocket.close` can return
`Timeout` or `ConnectionDown` after a successful peer close handshake:
the normal `gun_down` confirmation goes only to the owner. Prefer keeping
the opener and WebSocket receiver in the same process.
Closing in another process does not drain that receiver's mailbox. Do not
redirect a high-level `connect` handshake away from the calling process.
The internal `websocket/raw` module is not a supported application interface.

See the [message reference](/reference/gluegun-message/), [request reference](/reference/gluegun-request/), and [WebSocket guide](/guides/websockets/) for the full API around these concepts.
