---
title: What is Gluegun?
description: Learn what Gluegun does and when to use it.
---

Gluegun gives Gleam applications typed access to [Gun](https://ninenines.eu/docs/en/gun/), an asynchronous Erlang HTTP client. Gun speaks HTTP/1.1, HTTP/2, and WebSockets over HTTP/1.1, and it delivers each response as a series of messages. Gluegun gives those connections, requests, responses, messages, and WebSocket frames Gleam types. Because Gun runs only on the BEAM, Gluegun runs only on the Erlang target.

That message model is the reason to choose Gluegun. If you only need HTTP/1.1 requests with complete responses, [`gleam_httpc`](https://hexdocs.pm/gleam_httpc/) has a smaller API. Choose Gluegun when you need HTTP/2, WebSockets, streaming, cancellation, flow control, or direct connection management. [Choose an HTTP client](/choosing-a-client/) compares the options in detail.

## Two levels of control

Most requests do not need the message model. The high-level `gluegun/client` functions send one request on an open connection and collect the full response: status, headers, body, trailers, and all `1xx` informational responses.

When the response is too large to collect, or arrives over time, use the low-level modules instead. `gluegun/request` sends headers and chunked bodies and controls cancellation, flow, and flush. `gluegun/message` decodes the asynchronous messages that Gun sends back, including HTTP/2 push and upgrades. `gluegun/websocket` connects, sends, receives, and closes WebSockets.

Both levels use the same typed connection options for transport, protocol preference, and timeouts. Both levels also report failure the same way: they return `Result` values and do not throw exceptions.

## Connections hold the destination

Gluegun does not parse URLs, because a Gun connection already knows its host and port. Open a connection with `connection.options() |> connection.open(host: "example.com", port: 443)` and wait for protocol negotiation with `connection.await_up`. Then give request paths such as `/`, `/api/items`, or `/ws` to the HTTP or WebSocket functions.

If your application starts from full URLs, first parse them with the Gleam standard module `gleam/uri`. Use the parsed `host` and `port` for `connection.open`, and select the transport from the scheme. Then give the parsed path and query string to the HTTP or WebSocket functions.

## Module map

Gluegun has small submodules. Import only the modules that you use:

| Module | Purpose |
| --- | --- |
| [`gluegun/connection`](/reference/gluegun-connection/) | Open, configure, wait for, close, and shut down Gun connections. |
| [`gluegun/request`](/reference/gluegun-request/) | Low-level HTTP stream API: headers, chunked bodies, cancel, flow control. |
| [`gluegun/message`](/reference/gluegun-message/) | Decode and wait for asynchronous Gun stream messages. |
| [`gluegun/client`](/reference/gluegun-client/) | One-shot HTTP functions that collect a full response in memory. |
| [`gluegun/response`](/reference/gluegun-response/) | Examine collected `Response` values (status, headers, body, trailers, informational). |
| [`gluegun/websocket`](/reference/gluegun-websocket/) | WebSocket upgrade, reusable `Socket`, scoped `with_socket`, and low-level frame functions. |
| [`gluegun/tls`](/reference/gluegun-tls/) | Typed TLS client options for verification, versions, CAs, SNI, and mTLS. |
| [`gluegun/error`](/reference/gluegun-error/) | The `GluegunError` type that effectful APIs return. |
| [`gluegun/fin`](/reference/gluegun-fin/) | `Fin` / `NoFin` flags for the last chunk in a streamed body. |
| [`gluegun`](/reference/gluegun/) | Minimal facade that re-exports the most common functions. |

For full module, type, and function details, see the [API reference](/reference/).
