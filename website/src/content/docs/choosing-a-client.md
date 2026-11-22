---
title: Choose an HTTP client
description: Compare Gluegun with gleam_httpc, gleam_hackney, gleam_fetch, and Collie.
---

Choose a client for your target runtime and the part of the request lifecycle
your application must control. This comparison covers Gluegun 1.0 and the
linked package versions. It compares their public Gleam APIs, not every
feature of their underlying engines.

| Client | Runtime | Public API and fit |
| --- | --- | --- |
| [Gluegun](/reference/) | Erlang/BEAM | Gun connections and streams: HTTP/1.1, HTTP/2, and WebSockets over HTTP/1.1. Collect responses or control individual stream events. |
| [`gleam_httpc` 5.0](https://hexdocs.pm/gleam_httpc/5.0.0/gleam/httpc.html) | Erlang/BEAM | Complete HTTP/1.1 requests and responses through OTP's built-in client. A small API for ordinary HTTP calls. |
| [`gleam_hackney` 1.4](https://hexdocs.pm/gleam_hackney/1.4.0/gleam/hackney.html) | Erlang/BEAM | Complete HTTP requests and responses through Hackney. Its package docs recommend `gleam_httpc` for most uses. |
| [`gleam_fetch` 1.4.1](https://hexdocs.pm/gleam_fetch/1.4.1/gleam/fetch.html) | JavaScript | HTTP through Fetch in browsers and compatible runtimes. Collect bodies or read response chunks; the runtime manages connections and protocol selection. |
| [Collie 3.0](https://hexdocs.pm/collie/3.0.0/collie.html) | Erlang/BEAM | WebSocket-only actor client with stateful callbacks, custom messages and selectors, supervision helpers, and frame/message size limits. |

[`websocks`](https://hexdocs.pm/websocks/4.0.1/) provides WebSocket protocol
utilities for building clients and servers. It is not a complete HTTP client.

## Use Gluegun for connections and streams

Among these clients, Gluegun combines explicit BEAM connection and HTTP stream
handles with HTTP/2 and WebSockets. Choose it when your application needs to
control the exchange after dispatch:

- Keep a connection to one origin and reuse it across requests. You open it,
  await readiness, and choose when to shut it down or terminate it. Keep the
  opening process alive; passing a handle does not transfer ownership.
  See [connection ownership](/advanced/message-flow/#process-ownership-and-reply_to).
- Produce an upload in chunks with `request.start_stream` and `request.data`,
  or process download chunks with `message.await`. This suits generated uploads
  and downloads that you write to disk instead of collecting in memory.
  Streamed uploads do not accept `Content-Length`.
  See [Streaming](/guides/streaming/).
- Set finite response credit with `request.with_initial_flow`, then add credit
  with `request.update_flow` as your consumer processes data. You can inspect
  headers before retaining body data and cancel a stream you no longer need.
  Credit counts data messages, not bytes, and is not a strict memory cap.
  See [flow control](/guides/streaming/#finite-response-credit).
- Offer HTTP/2 through TLS ALPN, inspect the negotiated protocol, and start
  concurrent streams on that connection. With the low-level API, you can
  await or cancel a server-pushed stream.
  See [HTTP/2](/guides/http2/) and the [request API](/reference/gluegun-request/).
- Handle typed `Inform`, `Response`, `Data`, and `Trailers` events, or test a
  WebSocket upgrade and frame exchange from a BEAM application.
  See [Message Flow](/advanced/message-flow/) and [WebSockets](/guides/websockets/).

For a custom mailbox loop, [`message.decode`](/reference/gluegun-message/#decode)
preserves each event's connection and stream identity. Receiving raw Gun
messages this way requires your own Erlang FFI; Gluegun does not supply an HTTP
selector adapter. Collie provides custom selector integration for its
WebSocket actor, so this is not a reason to prefer Gluegun for WebSockets alone.

These controls require lifecycle and cleanup code. For ordinary responses,
[`gluegun/client`](/reference/gluegun-client/) collects the body, trailers, and
informational responses on an existing connection. For streaming, you own the
receive loop, byte limits, and cleanup. Read the
[limitations](/advanced/limitations/), including the HTTP/1.1 connection-reuse
restriction after cancellation with exhausted flow credit.

## Use a simpler client or a WebSocket actor

For scripts, webhooks, or REST calls that fit in memory, choose `gleam_httpc`
unless you need these lower-level controls. Its Gleam API has timeout and
redirect settings but no stream handles or streaming body API. OTP manages
connections. With Gluegun, you also handle redirects in application code.
The [`gleam_hackney` package docs](https://hexdocs.pm/gleam_hackney/1.4.0/)
recommend `gleam_httpc` for most uses; its wrapper exposes full-response
`send` and `send_bits`, not Hackney's full engine API.

For JavaScript, choose `gleam_fetch`. Its `stream_body` and `read_chunk`
functions support streamed downloads, so response streaming is not unique
to Gluegun. In a browser, requests follow
[Fetch's CORS rules](https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API/Using_Fetch#making_cross-origin_requests).
Gluegun does not run on JavaScript.

For a stateful WebSocket session, choose Collie if you want an actor with
callbacks and custom process messages. Choose Gluegun if you need HTTP
streams as well, or want to manage Gun connections and frame receives yourself.

## Shared HTTP methods

Gluegun uses `gleam/http.Method`, including `Other` for extension methods,
so callers do not need to convert a second method enum. It keeps its own
request builder because Gun accepts paths on an existing connection, not full
URLs. Gluegun does not accept `gleam/http/request.Request` records.
Its collected response wraps a standard `gleam/http/response.Response(BitArray)`
and retains trailers and informational responses alongside it.
See [Basic Requests](/guides/basic-requests/).
