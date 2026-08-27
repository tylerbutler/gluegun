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

The high-level `gluegun/client` functions use this flow internally for usual request and response work. They collect the full response in memory by design. They reject protocol messages such as push, upgrades, and WebSocket frames.

## `message.await` and `message.await_body`

- `message.await(conn, stream, timeout)` returns the *next* message for a stream as a typed `Message`. Use it in a loop to process `Inform`, `Response`, `Data`, `Trailers`, `Push`, `Upgrade`, and `WebSocket` values explicitly. This is the correct option for streams, server push, upgrade flows, or when you apply backpressure.
- `message.await_body(conn, stream, timeout)` collects body chunks until `Fin` and returns the bytes as one value. Call it only after you receive the `Response` message (for example, from a previous `await`). The full body stays in memory. If the response ends with trailers, `await_body` still returns the body, but it discards the trailer headers. Use `await` when you must get the trailers.
- `message.decode(gun_message)` changes a raw Gun term into a typed `Message`. It accepts the mailbox tuples that Gun sends to the process that owns the stream (`gun_response`, `gun_data`, `gun_inform`, `gun_trailers`, `gun_push`, `gun_upgrade`, `gun_ws`). It also accepts the shorter terms that `gun:await/3` returns. Use it when your own Erlang FFI receives Gun messages outside the Gluegun functions.

For chunked bodies, see the [streaming guide](/guides/streaming/). For WebSocket upgrade flows, see the [websockets guide](/guides/websockets/).

## `await_up` and the negotiated protocol

Gun `open/2` returns immediately after it starts the connection process. The socket connect and the protocol negotiation occur asynchronously. `connection.await_up` waits for the Gun `up` message and returns the negotiated `Protocol`.

The returned `Protocol` is the protocol that Gun selected. For TLS connections, this includes the ALPN result. If you do not call `await_up`, later stream messages still queue correctly and the connection can still work. But your code cannot know if Gun negotiated HTTP/1.1 or HTTP/2. This is important for decisions such as `websocket.upgrade_with_protocol`, which rejects `Http2` before it calls Gun.

## `close` and `shutdown`

`connection.close` is graceful. Gun sends its shutdown signal, stops new work on that connection, and waits for the process to exit. Use `close` when you control the connection lifecycle and the peer must see a clean end of the connection.

`connection.shutdown` is immediate. It stops the Gun process without a graceful close. Use `shutdown` only when a connection seems stuck. Open streams are canceled in both cases.

## `Fin` and `NoFin`: HTTP is half-closed

Gluegun shows the half-close model of Gun with `gluegun/fin.Fin` and `gluegun/fin.NoFin`.

On the request side, `request.data(conn, stream, fin.NoFin, chunk)` sends more bytes and tells Gun that the request body is not complete. `fin.Fin` on the last chunk tells Gun that there are no more request bytes. This final signal lets many servers start the response.

On the response side, `message.Response(fin, status, headers)` tells you if the final response has only headers (`fin.Fin`) or if body data follows (`fin.NoFin`). Later `message.Data(fin, data)` chunks use the same signal. `fin.Fin` means that the server has sent the full body. `fin.NoFin` means that more data follows. Response trailers, when present, arrive separately as `message.Trailers`.

## Cancellation

`request.cancel(conn, stream)` cancels one stream, not the full connection. After a successful cancellation, no more messages arrive for that stream. The Gun connection stays open. You can use it for other requests or streams.

Thus cancellation is a stream-local cleanup tool. Cancel the work that you do not use. Then continue to use the connection that you already opened.

## Flow control

Gun keeps flow control for each stream. `request.update_flow(conn, stream, increment)` tells the peer that it can send more data.

For HTTP/2 streams, the increment is in bytes. Gun starts from its default initial window (the HTTP/2 default of `65535` bytes, unless configured differently). HTTP/1.1 has no window for each stream, so `update_flow` has no effect on the protocol. Use it only when your application controls how much response data the peer can send next.

## WebSocket frame model

`message.WebSocket(frame)` holds typed WebSocket frames. Gluegun keeps text, binary, ping, pong, and close frames as different variants. It does not merge them into one shape.

Gun processes ping and pong automatically by default. `websocket.with_silence_pings` controls if automatic ping processing stays hidden, or if ping frames are visible to your code. `Ping` and `Pong` each hold a payload `BitArray`. An empty payload is valid. It means that no application data was attached.

`message.CloseWithReason(code, reason)` keeps the close reason as raw bytes. RFC 6455 says that the reason payload is UTF-8 text. Gluegun keeps it as a `BitArray`. Thus the caller decides when and how to decode it safely.

## Process ownership and `reply_to`

Gun sends asynchronous connection and stream messages to the Erlang process that called `gun:open`. To send WebSocket upgrade and frame messages to a different process, use `websocket/raw.with_reply_to`. It sets the Gun `reply_to` option to that process identifier.

If the receiving process stops before it processes the messages, those messages are lost. Gluegun does not keep them in a different location.

```gleam
import gleam/erlang/process
import gluegun/connection
import gluegun/websocket
import gluegun/websocket/raw

pub fn upgrade_in_current_process(conn) {
  let options =
    websocket.upgrade_options()
    |> raw.with_reply_to(reply_to: process.self())

  let assert Ok(protocol) =
    connection.await_up(conn, connection.Milliseconds(5000))

  let assert Ok(stream) =
    websocket.upgrade_with_protocol_and_options(
      conn,
      protocol,
      "/ws",
      [],
      options,
    )

  stream
}
```

See the [message reference](/reference/gluegun-message/), [request reference](/reference/gluegun-request/), and [WebSocket guide](/guides/websockets/) for the full API around these concepts.
