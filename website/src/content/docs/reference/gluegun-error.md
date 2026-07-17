---
title: gluegun/error
description: Error types returned by Gluegun effectful APIs.
---

Error types returned by Gluegun effectful APIs.

 Match variants such as `Timeout`, `ConnectionDown`, and `InvalidMessage`
 for application-specific recovery, and keep a fallback for Erlang or decode
 errors.

## Types

### `GluegunError`

Errors returned by Gluegun connection, request, message, and WebSocket APIs.

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

Gun reported the connection went down. The string carries Gun's reason.
 Reopen the connection before retrying.

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

Gun delivered a message Gluegun could not classify, or the high-level
 `client` helpers received push/upgrade/WebSocket on a regular request.
 Use the low-level `request`/`message` APIs for those flows.

##### `UnsupportedFeature(String)`

The requested feature is not supported (e.g. WebSocket over HTTP/2).
 Choose an alternative protocol or transport.

##### `ErlangError(String)`

A generic Erlang-side error that did not match a tagged shape. Inspect
 the reason string for debugging.

##### `DecodeError(String)`

A response body, frame, or message could not be decoded into the
 expected Gleam type. Often a UTF-8 or protocol-shape mismatch.
