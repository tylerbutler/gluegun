---
title: Production Checklist
description: Make sure that a Gluegun integration is ready for production.
---

Use this checklist before you ship Gluegun in a production BEAM service. It does not replace the guides. It points to the decisions that must be explicit before you deploy.

## Runtime and connection model

| Decision | Ready for production when | Read next |
|---|---|---|
| Runtime target | The service runs on Erlang. Gluegun is an interface to Erlang Gun. It does not support the JavaScript target. | [Limitations: Erlang target only](/advanced/limitations/#erlang-target-only) |
| Connection boundary | You open a Gun connection with a host and port. Then you give paths such as `/`, `/api/items`, or `/ws` to the request functions. Gluegun does not parse full URLs. Callers that accept full URLs parse them first with `gleam/uri`. | [What Gluegun does not do](/introduction/#what-gluegun-does-not-do) |
| Protocol readiness | The code waits for `connection.await_up` before it sends requests or upgrades WebSockets. | [Quick Start: key idea](/quick-start/#key-idea) |
| Connection ownership | One process owns, or waits for, the Gun stream messages for a request flow. The high-level `client` functions read messages on the calling process during `send`. | [Limitations: connection ownership](/advanced/limitations/#connection-ownership-is-important) |

## Transport and TLS

| Decision | Ready for production when | Read next |
|---|---|---|
| HTTPS baseline | TLS connections use the secure defaults of Gluegun: peer verification, hostname check, OS trust store, TLS 1.3/1.2, SNI, and a chain-depth limit. | [TLS: secure by default](/guides/tls/#secure-by-default) |
| Minimal containers | Each container has an OS CA store, or supplies CA material with `tls.with_cacertfile` or `tls.with_cacerts`. | [TLS: no system CA fallback](/guides/tls/#secure-by-default) |
| Custom TLS policy | Each TLS field that you change is intentional, reviewed, and documented by the application. | [TLS: change the baseline](/guides/tls/#change-the-baseline) |
| Insecure mode | `tls.insecure()` is used only for local development or trusted test networks. It is not used for production endpoints. | [TLS: insecure mode for development only](/guides/tls/#insecure-mode-for-development-only) |

:::danger[Do not ship insecure TLS]
`tls.insecure()` disables the protections that make HTTPS safe. If a production endpoint uses a private CA, add that CA explicitly. Do not disable verification.
:::

## Requests, timeouts, and errors

| Decision | Ready for production when | Read next |
|---|---|---|
| Timeout policy | Each connection, request, and message receive uses a timeout that agrees with the latency budget of the caller. `connection.Infinity` is used only for flows that can wait without a limit by design. | [Quick Start: timeout value](/quick-start/#key-idea) |
| Error handling | Effectful calls pattern match on `Result(_, error.GluegunError)`. Expected failures such as `Timeout` and `ConnectionDown` have explicit handling. | [Error Handling](/advanced/error-handling/) |
| Unexpected failures | Logs keep the formatted reason for unexpected Erlang or decode errors. Then you can find missing typed wrappers or upstream Gun behavior. | [Troubleshooting: unexpected Erlang error](/advanced/troubleshooting/#unexpected-erlang-error) |
| UTF-8 bodies | The code uses `response.body_text` only when text is expected. It uses `response.body` for binary payloads. | [Basic Requests: examine responses](/guides/basic-requests/#examine-responses) |

## Collected bodies and streams

Select the highest-level API that agrees with the shape of the response.

| Use | Applicable when | Not applicable when |
|---|---|---|
| `gluegun/client` | One usual response can be collected fully in memory. You get status, headers, body, trailers, and `1xx` informational responses in one typed value. | The body can be large or without limit. Or you must get chunks, trailers as they arrive, flow control, HTTP/2 push, upgrades, or WebSocket frames. |
| `gluegun/request` + `gluegun/message` | The application must get streamed response chunks, chunked request bodies, cancellation, flow-control updates, or raw Gun stream events. | A collected response is sufficient. |
| `gluegun/websocket` | The connection is HTTP/1.1 and the application uses WebSocket frames. | The negotiated protocol is HTTP/2. Gun does not support WebSocket over HTTP/2. |

Read the detailed API boundaries in [Basic Requests](/guides/basic-requests/#when-to-use-the-client-functions), [Streaming](/guides/streaming/), and [WebSockets](/guides/websockets/).

## Protocol checks

| Decision | Ready for production when | Read next |
|---|---|---|
| HTTP/2 preference | TLS connections list `[Http2, Http1]` only when HTTP/1.1 fallback is acceptable. The code checks the protocol that `connection.await_up` returns when the behavior depends on it. | [HTTP/2: how fallback works](/guides/http2/#how-fallback-works) |
| HTTP/2 server push | Push streams are processed or canceled with the low-level message and request APIs. The high-level `client` functions reject push with `InvalidMessage`. | [Streaming: message sequence](/guides/streaming/#message-sequence) |
| WebSocket protocol | WebSocket flows use HTTP/1.1. Low-level upgrades check the negotiated protocol before they call Gun. | [WebSockets: HTTP/2 not supported](/guides/websockets/) |
| Upgrade order | Low-level WebSocket code calls `websocket.await_upgrade` before it reads application frames. | [WebSockets: low-level upgrade flow](/guides/websockets/#low-level-upgrade-flow) |

## Cleanup and operations

| Decision | Ready for production when | Read next |
|---|---|---|
| Usual teardown | The code calls `connection.close` when the work is complete. | [Quick Start: close or shutdown](/quick-start/#key-idea) |
| Stuck connections | The code uses `connection.shutdown` only for connections that seem stuck, because `shutdown` stops the Gun process immediately. | [Limitations: close and shutdown](/advanced/limitations/#close-and-shutdown) |
| Reusable WebSockets | The code sends a WebSocket close frame and closes the connection below it, or it uses `websocket.with_socket` for scoped cleanup. | [Troubleshooting: WebSocket connection stays open](/advanced/troubleshooting/#websocket-connection-stays-open) |
| First diagnostic path | Runbooks tell operators to check host, port, transport, and timeout; URL path handling; the client or stream API selection; and the WebSocket upgrade order. | [Troubleshooting](/advanced/troubleshooting/) |

## Summary before you ship

Before you deploy, the integration must have explicit answers to these questions:

1. Which process owns the connection and waits for stream messages?
2. Which timeout applies to connection readiness, request send, and message receive?
3. Can each response that `client` processes fit in memory?
4. What occurs on `Timeout`, `ConnectionDown`, `InvalidMessage`, and unexpected Erlang errors?
5. How does each runtime environment supply the TLS trust roots?
6. Are WebSocket connections limited to HTTP/1.1 and closed fully?
7. Does the service close usual connections and use shutdown only for stuck ones?

If an answer is not clear, read [Error Handling](/advanced/error-handling/), [Limitations](/advanced/limitations/), and [Troubleshooting](/advanced/troubleshooting/) before you ship.
