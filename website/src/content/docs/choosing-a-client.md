---
title: Choose an HTTP client
description: Decide when to use Gluegun instead of gleam_httpc.
---

Gluegun and [`gleam_httpc`](https://hexdocs.pm/gleam_httpc/) serve different needs. `gleam_httpc` provides a small request-and-response API over Erlang/OTP's built-in HTTP client. Gluegun provides typed access to Gun connections, streams, HTTP/2, and WebSockets.

| Need | `gleam_httpc` | Gluegun |
| --- | --- | --- |
| Send a usual HTTP request and collect one response | Yes | Yes, with `gluegun/client` |
| Use an HTTP client included with Erlang/OTP | Yes | No; Gluegun depends on Gun |
| Follow redirects through a configuration option | Yes | Handle redirects in application code |
| Use HTTP/2 | No | Yes |
| Open a WebSocket | No | Yes, over HTTP/1.1 |
| Stream request or response bodies | The Gleam package does not expose streaming | Yes |
| Cancel one request stream | No | Yes |
| Control flow and backpressure | No | Yes |
| Receive trailers, `1xx` responses, or HTTP/2 push | No | Yes |
| Manage a persistent connection directly | No | Yes |

## Use `gleam_httpc` for simple requests

Choose `gleam_httpc` when your application sends usual REST or JSON requests, uses HTTP/1.1, and can keep the full response body in memory. Its API accepts a complete URL and returns a complete response. OTP manages the underlying client service.

This model works well for scripts, webhooks, and service-to-service requests that do not need protocol-level control.

## Use Gluegun for connections and streams

Choose Gluegun when your application needs one or more of these features:

- HTTP/2 protocol negotiation and concurrent streams.
- WebSocket connections.
- Incremental request or response bodies.
- Stream cancellation or flow-control updates.
- Long-lived connections to one origin.
- Explicit handling of trailers, informational responses, pushes, or upgrades.

Gluegun requires more lifecycle code. You open a connection, wait for protocol negotiation, start a request or upgrade, and close the connection when you finish. The high-level [`gluegun/client`](/reference/gluegun-client/) API handles the usual collected-response case. The lower-level request and message APIs keep Gun's stream events visible.

## Test WebSocket servers

An HTTP request client cannot test a WebSocket session. End-to-end tests need a client that can perform the HTTP upgrade and then send and receive WebSocket frames. Gluegun can test the upgrade, application messages, control frames, and disconnect flow without a browser or a Node.js process.

See [WebSockets](/guides/websockets/) for the Gluegun client API and [Basic Requests](/guides/basic-requests/) for collected HTTP responses.
