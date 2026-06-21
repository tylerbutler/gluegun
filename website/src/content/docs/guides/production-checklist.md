---
title: Production Checklist
description: Decide whether a Gluegun integration is ready for production.
---

Use this checklist before shipping Gluegun in a production BEAM service. It does not replace the guides; it points to the decisions that should be explicit before deploy.

## Runtime and connection model

| Decision | Production-ready when | Read next |
|---|---|---|
| Runtime target | The service runs on Erlang. Gluegun wraps Erlang Gun and does not support the JavaScript target. | [Limitations: Erlang target only](/advanced/limitations/#erlang-target-only) |
| Connection boundary | You open a Gun connection with a host and port, then pass paths such as `/`, `/api/items`, or `/ws` to request helpers. Gluegun does not parse full URLs; callers that accept full URLs parse them first with `gleam/uri`. | [What Gluegun does not do](/introduction/#what-gluegun-does-not-do) |
| Protocol readiness | Code waits for `connection.await_up` before sending requests or upgrading WebSockets. | [Quick Start: key idea](/quick-start/#key-idea) |
| Connection ownership | One process owns or awaits the Gun stream messages for a request flow. High-level `client` helpers consume messages on the calling process while `send` runs. | [Limitations: connection ownership](/advanced/limitations/#connection-ownership-matters) |

## Transport and TLS

| Decision | Production-ready when | Read next |
|---|---|---|
| HTTPS baseline | TLS connections rely on Gluegun's secure defaults: peer verification, hostname checking, OS trust store, TLS 1.3/1.2, SNI, and chain-depth limit. | [TLS: secure by default](/guides/tls/#secure-by-default) |
| Minimal containers | Containers either expose an OS CA store or provide CA material with `tls.with_cacertfile` or `tls.with_cacerts`. | [TLS: no system CA fallback](/guides/tls/#secure-by-default) |
| Custom TLS policy | Any overridden TLS fields are intentional, reviewed, and documented by the application. | [TLS: overriding the baseline](/guides/tls/#overriding-the-baseline) |
| Insecure mode | `tls.insecure()` is used only for local development or trusted test networks, never production endpoints. | [TLS: development-only insecure mode](/guides/tls/#development-only-insecure-mode) |

:::danger[Do not ship insecure TLS]
`tls.insecure()` disables the protections that make HTTPS trustworthy. If a production endpoint needs a private CA, add that CA explicitly instead of disabling verification.
:::

## Requests, timeouts, and errors

| Decision | Production-ready when | Read next |
|---|---|---|
| Timeout policy | Every connection, request, and message receive uses a timeout that matches the caller's latency budget. `connection.Infinity` is reserved for flows that can wait forever by design. | [Quick Start: timeout value](/quick-start/#key-idea) |
| Error handling | Effectful calls pattern match on `Result(_, error.GluegunError)`, with explicit handling for expected failures such as `Timeout` and `ConnectionDown`. | [Error Handling](/advanced/error-handling/) |
| Unexpected failures | Logs preserve the formatted reason for unexpected Erlang or decode errors so you can diagnose missing typed wrappers or upstream Gun behavior. | [Troubleshooting: unexpected Erlang error](/advanced/troubleshooting/#unexpected-erlang-error) |
| UTF-8 bodies | Code uses `response.body_text` only when text is expected and falls back to `response.body` for binary payloads. | [Basic Requests: inspecting responses](/guides/basic-requests/#inspecting-responses) |

## Collected bodies versus streams

Choose the highest-level API that still matches the response shape.

| Use | Fits when | Avoid when |
|---|---|---|
| `gluegun/client` | One regular response can be collected fully in memory. You want status, headers, body, trailers, and `1xx` informational responses in one typed value. | The body may be large or unbounded, or you need chunks, trailers as they arrive, flow control, HTTP/2 push, upgrades, or WebSocket frames. |
| `gluegun/request` + `gluegun/message` | The application needs streamed response chunks, chunked request bodies, cancellation, flow-control updates, or raw Gun stream events. | A simple collected response is enough. |
| `gluegun/websocket` | The connection is HTTP/1.1 and the application needs WebSocket frames. | The negotiated protocol is HTTP/2. Gun does not support WebSocket over HTTP/2. |

Read the detailed API boundaries in [Basic Requests](/guides/basic-requests/#when-to-use-the-client-helpers), [Streaming](/guides/streaming/), and [WebSockets](/guides/websockets/).

## Protocol-specific checks

| Decision | Production-ready when | Read next |
|---|---|---|
| HTTP/2 preference | TLS connections list `[Http2, Http1]` only when HTTP/1.1 fallback is acceptable. Code checks the protocol returned by `connection.await_up` when behavior depends on it. | [HTTP/2: how fallback works](/guides/http2/#how-fallback-works) |
| HTTP/2 server push | Push streams are handled or canceled with the low-level message/request APIs. High-level `client` helpers reject push with `InvalidMessage`. | [Streaming: message sequencing](/guides/streaming/#message-sequencing) |
| WebSocket protocol | WebSocket flows use HTTP/1.1. Low-level upgrades check the negotiated protocol before calling Gun. | [WebSockets: HTTP/2 not supported](/guides/websockets/) |
| Upgrade ordering | Low-level WebSocket code calls `websocket.await_upgrade` before reading application frames. | [WebSockets: low-level upgrade flow](/guides/websockets/#low-level-upgrade-flow) |

## Cleanup and operations

| Decision | Production-ready when | Read next |
|---|---|---|
| Normal teardown | Code calls `connection.close` when work is finished. | [Quick Start: close or shutdown](/quick-start/#key-idea) |
| Stuck connections | Code reserves `connection.shutdown` for suspected stuck connections because it terminates the Gun process immediately. | [Limitations: close versus shutdown](/advanced/limitations/#close-versus-shutdown) |
| Reusable WebSockets | Code sends a WebSocket close frame and closes the underlying connection, or uses `websocket.with_socket` for scoped cleanup. | [Troubleshooting: WebSocket connection stays open](/advanced/troubleshooting/#websocket-connection-stays-open) |
| First diagnostic path | Runbooks point operators to host/port/transport/timeout checks, URL path handling, client-versus-stream API choice, and WebSocket upgrade order. | [Troubleshooting](/advanced/troubleshooting/) |

## Ship-ready summary

Before deploy, the integration should have explicit answers for:

1. Which process owns the connection and awaits stream messages?
2. Which timeout applies to connection readiness, request send, and message receive?
3. Can every response handled by `client` fit in memory?
4. What happens on `Timeout`, `ConnectionDown`, `InvalidMessage`, and unexpected Erlang errors?
5. How are TLS trust roots supplied in each runtime environment?
6. Are WebSocket connections constrained to HTTP/1.1 and closed completely?
7. Does the service close normal connections and reserve shutdown for stuck ones?

If any answer is unclear, start with [Error Handling](/advanced/error-handling/), [Limitations](/advanced/limitations/), and [Troubleshooting](/advanced/troubleshooting/) before shipping.
