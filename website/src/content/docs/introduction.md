---
title: What is Gluegun?
description: Learn what Gluegun does and when to use it.
---

Gluegun is a Gleam interface to the Erlang [Gun](https://ninenines.eu/docs/en/gun/) HTTP client.

Gun is an asynchronous HTTP client. It supports HTTP/1.1, HTTP/2, and WebSocket over HTTP/1.1. Gluegun gives Gleam code typed functions for connections, requests, responses, messages, and WebSockets. Gluegun keeps access to the stream model of Gun.

Gun is Erlang only. Thus Gluegun runs only on the Erlang target.

## What Gluegun gives you

- Typed connection options for transport, protocol preference, and timeouts.
- Low-level request functions for headers, chunked bodies, cancellation, flow control, and flush.
- Message decoders for asynchronous Gun stream messages.
- High-level HTTP functions. These send one request on an open connection and collect the full response (status, headers, body, trailers, and all `1xx` informational responses).
- WebSocket functions to connect, send, receive, and close.
- `Result` error values. Gluegun does not throw exceptions.

## What Gluegun does not do

Gluegun does not parse URLs. Open a connection with `connection.options() |> connection.open(host: "example.com", port: 443)`. Wait for protocol negotiation with `connection.await_up`. Then give request paths such as `/`, `/api/items`, or `/ws` to the HTTP or WebSocket functions.

If your application starts from full URLs, first parse them with the Gleam standard module `gleam/uri`. Use the parsed `host` and `port` for `connection.open`. Select the transport from the scheme. Give the parsed path and query string to the HTTP or WebSocket functions.

Gluegun does not hide the stream model of Gun. The high-level client functions are sufficient for usual responses. For streamed bodies, HTTP/2 push, upgrades, WebSocket messages, cancellation, and flow-control updates, use `gluegun/request` and `gluegun/message`.

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
