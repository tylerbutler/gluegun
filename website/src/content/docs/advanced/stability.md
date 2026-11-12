---
title: Stability
description: Semantic versioning and compatibility guarantees for Gluegun.
---

Gluegun 1.0 uses semantic versioning.

## Stable public API

The public modules are `gluegun`, `gluegun/client`, `gluegun/connection`,
`gluegun/error`, `gluegun/fin`, `gluegun/message`, `gluegun/request`,
`gluegun/response`, `gluegun/tls`, and `gluegun/websocket`.

Maintainers treat removal or changes to existing signatures, argument labels,
record fields, or documented behavior as major-release changes. New functions
and compatible options require a minor release. Bug fixes and documentation
corrections require a patch release.

The root `gluegun` facade supports a complete basic HTTP lifecycle. Use the
named modules for request customization, streaming, and WebSockets.

## Public types

Treat public sum types as closed. Adding a variant can break an exhaustive
pattern match, so it requires a major release. This applies to connection
`Transport`, `Protocol`, and `AddressFamily`; `message.Message`, `Frame`, and
`Envelope`; `error.GluegunError`; `fin.Fin`; `response.Informational`; and TLS
`VerifyMode`, `TlsVersion`, and `ServerNameIndication`. Public record changes
follow the same rule, including the WebSocket handshake record.

Request and push methods use `gleam/http.Method`, which `gleam_http` owns.
Gluegun does not define a second method enum. The declared dependency range
controls which upstream versions a consumer can resolve.

Opaque types remain stable through their documented operations. Their private
fields and runtime representation can change without notice. `Connection` and
`Stream` are distinct external handles: their type identity matters, but callers
must not depend on the underlying process/reference representation or construct
them through untyped casts.

Error variants and payload types are stable. Reason strings are diagnostics:
log them, but do not parse them as stable error codes.

## Internal code

Items marked `@internal`, including encoded options and test helpers, are not
stable API even when Gleam permits an import. Neither `gluegun/internal` nor
`gluegun/websocket/raw` is a public module. Internal functions and representations
can change in any release. Guides use public operations rather than internal
constructors.

## Supported versions

Gluegun targets Erlang only and declares these bounds:

- Erlang/OTP `>= 27`.
- Gleam `>= 1.11.0`.
- Gun `>= 2.1.0 and < 3.0.0`.
- `gleam_stdlib >= 0.53.0 and < 2.0.0`.
- `gleam_erlang >= 1.0.0 and < 2.0.0`.
- `gleam_http >= 4.0.0 and < 5.0.0`.

The compatibility CI job builds a separate consumer with minimum production
dependencies and a current compatible set. It excludes Gluegun's test-runner
dependencies and exercises public HTTP, WebSocket upgrade/adoption,
subprotocols, and finite-credit close against loopback peers. The current set
also runs the root bounded-streaming suite, including real HTTP/2 push arrival
and cleanup, flow control, and TLS trust and hostname verification over IPv4
and IPv6. The pinned root suite covers these and additional WebSocket wire
contracts.

The minimum compiler and standard library bounds follow `gleam_erlang` 1.0:
it requires Gleam 1.11 and `gleam_stdlib` 0.53. Earlier Gluegun declarations
of 1.7 and 0.48 did not form an installable minimum dependency set.

See [limitations](/advanced/limitations/) for the accepted upstream
HTTP/1.1 flow-paused cancellation defect in 1.0.
