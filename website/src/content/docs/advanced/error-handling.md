---
title: Error Handling
description: Work with GluegunError values returned from public operations.
---

Effectful operations that open connections, send requests, await messages, decode response bodies, or send WebSocket frames return `Result(_, error.GluegunError)`. Pure builders and accessors return plain values.

Pattern match on variants that matter to your application and keep a fallback for unexpected Erlang or decode errors.

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

Gluegun normalizes FFI errors at the API boundary so Erlang failures become `GluegunError` values instead of leaking raw Erlang terms.

## Error variants

| Variant | Meaning | Common cause |
| --- | --- | --- |
| `Timeout` | An operation timed out. | The server was slow, unreachable, or the timeout was too short. |
| `ConnectionDown(String)` | The Gun connection went down. | The remote closed the connection or the network failed. |
| `ConnectionError(String)` | Connection setup or use failed. | Bad host, port, transport, TLS, or Gun connection state. |
| `StreamError(String)` | A stream-specific failure occurred. | A stream was canceled, reset, or rejected. |
| `InvalidOptions(String)` | Gluegun rejected invalid typed options. | A non-positive flow-control increment or unsupported option shape. |
| `InvalidMessage(String)` | A protocol message did not match the API being used. | Using high-level client helpers for upgrades, push, WebSocket messages, or receiving WebSocket frames before upgrade completion. |
| `ErlangError(String)` | An unclassified Erlang or FFI failure occurred. | An unexpected Gun or BEAM error crossed the FFI boundary. |
| `DecodeError(String)` | Decoding failed. | Invalid FFI message shape or a non-UTF-8 response body passed to `response.body_text`. |

See the [error reference](/reference/gluegun-error/) for the current error type definition.
