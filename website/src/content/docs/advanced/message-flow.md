---
title: Message Flow
description: Understand connection lifecycle, stream messages, flow control, and ownership.
---

Gluegun keeps Gun's asynchronous process model visible instead of hiding it behind a single blocking request API. That is what makes the lower-level `gluegun/request`, `gluegun/message`, and `gluegun/websocket` modules useful for streaming, push, upgrades, and long-lived connections.

The main flow is:

1. Open a connection with `gluegun/connection`.
2. Wait for the connection to become ready with `connection.await_up`.
3. Start a stream with `gluegun/request` or a WebSocket upgrade with `gluegun/websocket`.
4. Await typed `gluegun/message.Message` values for that stream.
5. Decide whether to keep streaming, add flow-control allowance, cancel, or close the connection.

High-level `gluegun/client` helpers use this flow internally for ordinary request/response work. They deliberately collect the full response in memory and reject protocol-specific messages such as push, upgrades, and WebSocket frames.

## `await_up` and negotiated protocol

Gun's `open/2` returns immediately after starting the connection process. The actual socket connect and protocol negotiation happen asynchronously. `connection.await_up` waits for Gun's `up` message and returns the negotiated `Protocol`.

That returned `Protocol` is the protocol Gun actually selected, including ALPN results for TLS connections. If you skip `await_up`, later stream messages still queue correctly and the connection can still work, but your code cannot know whether Gun negotiated HTTP/1.1 or HTTP/2. That matters for decisions like `websocket.upgrade_with_protocol`, which rejects `Http2` before calling Gun.

## `close` vs `shutdown`

`connection.close` is abrupt. Use it when you are tearing a connection down immediately and do not need in-flight streams to finish.

`connection.shutdown` is graceful. Gun sends HTTP/2 `GOAWAY` when appropriate, stops accepting new work on that connection, lets in-flight streams drain, and then closes the socket. Prefer `shutdown` when you own the connection lifecycle and want the peer to see a clean end-of-connection sequence.

## `Fin` and `NoFin`: HTTP is half-closed

Gluegun exposes Gun's half-close model with `gluegun/fin.Fin` and `gluegun/fin.NoFin`.

On the request side, `request.data(conn, stream, fin.NoFin, chunk)` says "here are more bytes, but the request body is not finished yet." Sending `fin.Fin` on the last chunk says "there are no more request bytes." That final signal is what allows many servers to begin producing a response.

On the response side, `message.Response(fin, status, headers)` tells you whether the final response has headers only (`fin.Fin`) or whether body data will follow (`fin.NoFin`). Later `message.Data(fin, data)` chunks use the same signal: `fin.Fin` means the server has finished sending the body, while `fin.NoFin` means more data is still coming. Response trailers, when present, arrive separately as `message.Trailers`.

## Cancellation post-conditions

`request.cancel(conn, stream)` cancels one stream, not the whole connection. After cancellation succeeds, no further messages should arrive for that stream. The underlying Gun connection remains open and can be reused for other requests or streams.

That makes cancellation a stream-local cleanup tool: cancel the work you no longer want, then keep using the connection you already paid to establish.

## Flow control

Gun maintains flow control per stream. `request.update_flow(conn, stream, increment)` advertises additional receive capacity to the peer.

For HTTP/2 streams the increment is measured in bytes, and Gun starts from its default initial window (the HTTP/2 default `65535` bytes unless configured otherwise). For HTTP/1.1 there is no per-stream window to extend, so `update_flow` is effectively a no-op from the protocol's perspective. Use it only when your application wants explicit control over how much response data the peer may send next.

## WebSocket frame model

`message.WebSocket(frame)` carries typed WebSocket frames. Gluegun preserves the distinction between text, binary, ping, pong, and close frames instead of collapsing them into a single catch-all shape.

Gun handles ping/pong automatically by default. `websocket.with_silence_pings` controls whether automatic ping handling stays invisible or whether ping frames are surfaced for your code to observe. `Ping` and `Pong` each carry a payload `BitArray`; an empty payload is valid and just means no application data was attached.

`message.CloseWithReason(code, reason)` preserves the close reason as raw bytes. RFC 6455 says the reason payload is UTF-8 text, but Gluegun keeps it as a `BitArray` so callers can decide when and how to decode it safely.

## Process ownership and `reply_to`

Gun sends asynchronous connection and stream messages to the Erlang process that called `gun:open`. If you want another process to receive WebSocket upgrade and frame messages, use `websocket.with_reply_to_dynamic` to set Gun's raw `reply_to` option.

If that receiving process dies before it handles the messages, those messages are lost. Gluegun does not buffer them elsewhere.

```gleam
import gleam/dynamic
import gleam/erlang/process
import gluegun/connection
import gluegun/websocket

pub fn upgrade_in_current_process(conn) {
  let owner = dynamic.from(process.self())
  let options =
    websocket.upgrade_options()
    |> websocket.with_reply_to_dynamic(reply_to: owner)

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

See the [message reference](/reference/gluegun-message/), [request reference](/reference/gluegun-request/), and [WebSocket guide](/guides/websockets/) for the full API surface around these concepts.
