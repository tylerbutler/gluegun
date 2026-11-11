---
title: gluegun/error
description: Error types returned by Gluegun effectful APIs.
---

Error types returned by Gluegun effectful APIs.

 Match variants such as `Timeout`, `ConnectionDown`, and `InvalidMessage`
 for application-specific recovery, and keep a fallback for Erlang or decode
 errors.

 Every Gluegun operation crosses the Erlang FFI boundary as
 `Result(value, GluegunError)`. `src/gluegun_ffi.erl` classifies each Gun
 failure and builds the matching variant, so no Gleam code has to inspect
 untyped Erlang error terms.

## Types

### `GluegunError`

Errors returned by Gluegun connection, request, message, and WebSocket APIs.

 Variant names and payload types are stable. Reason strings are diagnostic
 text, not stable codes: log them, but do not parse or match their contents.

 Match the variants relevant to your application and keep a fallback for
 `ErlangError` / `DecodeError`, which can occur when Gun returns shapes
 Gluegun cannot normalize.

```gleam
pub type GluegunError {
  Timeout
  ConnectionDown(String)
  ConnectionError(String)
  StreamError(String)
  InvalidOptions(String)
  InvalidMessage(String)
  UnsupportedFeature(String)
  ErlangError(String)
  DecodeError(String)
}
```

#### Constructors

##### `Timeout`

An operation did not complete within the configured `Timeout`. Retry,
 extend the timeout, or fall back to a degraded path.

##### `ConnectionDown(String)`

Gun reported that the connection went down, or its process exited.
 The string contains Gun's reason. Reopen the connection before retrying.

##### `ConnectionError(String)`

Gun could not establish or maintain the connection (DNS, TCP, TLS).
 Inspect the reason string and adjust transport or TLS options.

##### `StreamError(String)`

A stream-level error occurred (cancelled, reset, protocol error).
 Open a new stream; the connection may still be usable.

##### `InvalidOptions(String)`

Caller passed options Gun rejected (e.g. non-positive flow window).
 Fix the options and retry.

##### `InvalidMessage(String)`

An outgoing frame is invalid, or the high-level
 `client` helpers received push/upgrade/WebSocket on a regular request.
 Use the low-level `request`/`message` APIs for those flows.

##### `UnsupportedFeature(String)`

The requested feature is not supported (e.g. WebSocket over HTTP/2).
 Choose an alternative protocol or transport.

##### `ErlangError(String)`

A generic Erlang-side error that did not match a tagged shape. Inspect
 the reason string for debugging.

##### `DecodeError(String)`

Incoming data could not be decoded into the expected Gleam type,
 including malformed Gun messages and non-UTF-8 response headers.
