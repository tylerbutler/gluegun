---
title: Error Handling
description: Work with GluegunError values returned from public operations.
---

All public operations return `Result(_, error.GluegunError)`.

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

Gluegun routes FFI errors through `error.decode_ffi_error` or `gluegun/internal/ffi_result.gleam` so Erlang failures become Gleam values at the API boundary.
