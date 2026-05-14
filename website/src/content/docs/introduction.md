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
- High-level HTTP helpers that send one request on an existing connection and collect the full response body.
- WebSocket helpers for connecting, sending, receiving, and closing.
- `Result`-based error values instead of exceptions.

## What Gluegun does not do

Gluegun does not parse URLs. Open a connection with `connection.open(host, port, options)`, wait for protocol negotiation with `connection.await_up`, then pass request paths to HTTP or WebSocket helpers.

Gluegun also does not hide Gun's streaming model. The high-level client helpers are convenient for regular responses, but streaming bodies, HTTP/2 push, upgrades, WebSocket messages, cancellation, and flow-control updates belong in `gluegun/request` and `gluegun/message`.
