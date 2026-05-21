---
title: gluegun/error
description: Error types returned by Gluegun effectful APIs.
---

# `gluegun/error`

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

- `Timeout()`
- `ConnectionDown(String)`
- `ConnectionError(String)`
- `StreamError(String)`
- `InvalidOptions(String)`
- `InvalidMessage(String)`
- `UnsupportedFeature(String)`
- `ErlangError(String)`
- `DecodeError(String)`
