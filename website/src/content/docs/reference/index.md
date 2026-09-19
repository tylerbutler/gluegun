---
title: Reference
description: Generated Gluegun API reference from Gleam docs metadata.
---

This site is the primary reference for `gluegun` `0.1.0`. It is generated from the package metadata and includes every public type, function, and constant.

**Find a symbol:** open Search with `Ctrl+K` or `⌘K`, then enter a module, type, or function name.

## Start here

- [`gluegun`](/reference/gluegun/) — Minimal common-path facade for the Gluegun HTTP client wrapper.
- [`gluegun/client`](/reference/gluegun-client/) — High-level HTTP helpers for existing Gun connections.
- [`gluegun/connection`](/reference/gluegun-connection/) — Connection management for Erlang Gun.
- [`gluegun/request`](/reference/gluegun-request/) — Low-level HTTP request and stream operations.

## Streams and protocols

- [`gluegun/message`](/reference/gluegun-message/) — Decoding and awaiting asynchronous Gun stream messages.
- [`gluegun/fin`](/reference/gluegun-fin/) — Fin (final) flags for Gun HTTP streaming.
- [`gluegun/websocket`](/reference/gluegun-websocket/) — WebSocket helpers for Gun connections.

## Responses and security

- [`gluegun/response`](/reference/gluegun-response/) — HTTP response values collected by `gluegun/client`.
- [`gluegun/error`](/reference/gluegun-error/) — Error types returned by Gluegun effectful APIs.
- [`gluegun/tls`](/reference/gluegun-tls/) — Typed TLS client options for Gun and Erlang SSL.

For concepts and recommended patterns, use the [guides](/guides/basic-requests/) and [advanced topics](/advanced/error-handling/). HexDocs provides a [mirror of the API reference](https://hexdocs.pm/gluegun/).
