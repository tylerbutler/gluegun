---
title: What is Gluegun?
description: Learn what Gluegun wraps and when to use it.
---

Gluegun is a Gleam wrapper around the Erlang [Gun](https://ninenines.eu/docs/en/gun/) HTTP client.

Gun is an asynchronous HTTP client that supports HTTP/1.1, HTTP/2, and WebSocket over HTTP/1.1. Gluegun gives Gleam callers typed connection, request, response, message, and WebSocket helpers while preserving access to Gun's stream-oriented model.

Because Gun is Erlang-only, Gluegun targets the Erlang runtime.

## What Gluegun provides

- Typed connection options for transport, protocol preference, and timeouts.
- Low-level request helpers for headers, chunked bodies, cancellation, flow control, and flushing.
- Message decoders for asynchronous Gun stream messages.
- High-level HTTP helpers that send one request on an existing connection and collect the full response (status, headers, body, trailers, and any `1xx` informational responses).
- WebSocket helpers for connecting, sending, receiving, and closing.
- `Result`-based error values instead of exceptions.

## What Gluegun does not do

Gluegun does not parse URLs. Open a connection with `connection.options() |> connection.open(host: "example.com", port: 443)`, wait for protocol negotiation with `connection.await_up`, then pass request paths such as `/`, `/api/items`, or `/ws` to HTTP or WebSocket helpers.

If your application starts from full URLs, parse them first with Gleam's standard `gleam/uri` module. Use the parsed `host` and `port` for `connection.open`, choose the transport from the scheme, and pass the parsed path plus query string to Gluegun's HTTP or WebSocket helpers.

Gluegun also does not hide Gun's streaming model. The high-level client helpers are convenient for regular responses, but streaming bodies, HTTP/2 push, upgrades, WebSocket messages, cancellation, and flow-control updates belong in `gluegun/request` and `gluegun/message`.

## Module map

Gluegun is organized into focused submodules. Import the ones you need:

| Module | Purpose |
| --- | --- |
| [`gluegun/connection`](/reference/gluegun-connection/) | Open, configure, await, close, and shut down Gun connections. |
| [`gluegun/request`](/reference/gluegun-request/) | Low-level HTTP stream API: headers, chunked bodies, cancel, flow control. |
| [`gluegun/message`](/reference/gluegun-message/) | Decode and await asynchronous Gun stream messages. |
| [`gluegun/client`](/reference/gluegun-client/) | One-shot HTTP helpers that collect a full response in memory. |
| [`gluegun/response`](/reference/gluegun-response/) | Inspect collected `Response` values (status, headers, body, trailers, informational). |
| [`gluegun/websocket`](/reference/gluegun-websocket/) | WebSocket upgrade, reusable `Socket`, scoped `with_socket`, and low-level frame helpers. |
| [`gluegun/tls`](/reference/gluegun-tls/) | Typed TLS client options for verification, versions, CAs, SNI, and mTLS. |
| [`gluegun/error`](/reference/gluegun-error/) | The `GluegunError` type returned by effectful APIs. |
| [`gluegun/fin`](/reference/gluegun-fin/) | `Fin` / `NoFin` flags for the last chunk in a streamed body. |
| [`gluegun`](/reference/gluegun/) | Minimal facade re-exporting the most common helpers. |

For complete module, type, and function details, use the [API reference](/reference/).
