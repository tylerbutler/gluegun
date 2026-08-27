---
title: Error Handling
description: Use the GluegunError values that public operations return.
---

Effectful operations open connections, send requests, wait for messages, or send WebSocket frames. They return `Result(_, error.GluegunError)`. Pure builders and accessors return plain values. Only `response.body_text` decodes the body (UTF-8). `response.body` always returns the raw bytes.

Pattern match on the variants that are important to your application. Keep a fallback for unexpected Erlang or decode errors.

```gleam
import gleam/io
import gluegun/client
import gluegun/connection
import gluegun/error

fn safe_get(conn) {
  case client.get(conn, "/", [], connection.Milliseconds(5000)) {
    Ok(response) -> Ok(response)
    Error(error.Timeout) -> {
      io.println("request timed out")
      Error(error.Timeout)
    }
    Error(error.ConnectionDown(reason)) -> {
      io.println("connection down: " <> reason)
      Error(error.ConnectionDown(reason))
    }
    Error(other) -> {
      io.println("request failed")
      Error(other)
    }
  }
}
```

Gluegun normalizes FFI errors at the API boundary. Erlang failures become `GluegunError` values. Raw Erlang terms do not leak.

## Error variants

| Variant | Meaning | Common cause |
| --- | --- | --- |
| `Timeout` | An operation timed out. | The server was slow or not reachable, or the timeout was too short. |
| `ConnectionDown(String)` | The Gun connection went down. | The remote closed the connection, or the network failed. |
| `ConnectionError(String)` | Connection setup or use failed. | Incorrect host, port, transport, TLS, or Gun connection state. |
| `StreamError(String)` | A stream failure occurred. | A stream was canceled, reset, or rejected. |
| `InvalidOptions(String)` | Gluegun rejected the typed options. | A flow-control increment that is not positive, or an unsupported option shape. |
| `InvalidMessage(String)` | A protocol message did not agree with the API in use. | High-level client functions got an upgrade, push, or WebSocket message. Or the code received WebSocket frames before the upgrade was complete. |
| `UnsupportedFeature(String)` | The feature is not supported. | A WebSocket upgrade on an HTTP/2 connection (Gun does not support RFC 8441). Select `Http1`. |
| `ErlangError(String)` | An Erlang or FFI failure occurred that has no category. | An unexpected Gun or BEAM error crossed the FFI boundary. |
| `DecodeError(String)` | Decode failed. | An invalid FFI message shape, or a response body that is not UTF-8 given to `response.body_text`. |

See the [error reference](/reference/gluegun-error/) for the current error type definition.
