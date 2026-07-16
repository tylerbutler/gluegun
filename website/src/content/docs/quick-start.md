---
title: Quick Start
description: Send a basic GET request with Gluegun.
---

Open a Gun connection, wait for it to be ready, send a GET request, and collect the full response in memory.

```gleam
import gleam/int
import gleam/io
import gleam/result
import gluegun/client
import gluegun/connection
import gluegun/request
import gluegun/response

pub fn main() {
  let timeout = connection.Milliseconds(5000)

  use conn <- result.try(
    connection.options()
    |> connection.open(host: "example.com", port: 80),
  )
  use _protocol <- result.try(connection.await_up(conn, timeout))

  use res <- result.try(
    client.new(request.Get, "/")
    |> client.with_timeout(timeout: timeout)
    |> client.send(connection: conn),
  )

  io.println("status: " <> int.to_string(response.status(res)))

  case response.body_text(res) {
    Ok(text) -> io.println(text)
    Error(_) -> io.println("response body was not UTF-8")
  }

  connection.close(conn)
}
```

## Key idea

Gluegun separates connection setup from requests:

1. Open a connection to a host and port.
2. Wait for Gun to report the negotiated protocol.
3. Send requests using paths such as `/`, `/api/items`, or `/health`.
4. Close or shut down the connection when you are finished.

If you have a full URL instead of separate connection pieces, parse it with `gleam/uri` before calling Gluegun. Gluegun intentionally expects the already-separated host, port, transport, path, and query values.

`connection.Milliseconds(Int)` constructs a finite `Timeout`; use `connection.Infinity` when you want to wait without bound. The same `Timeout` value is reused for connection readiness, request bodies, and message receives.

Use `connection.close` for normal teardown. Use `connection.shutdown` only when a connection appears stuck — it terminates the Gun process immediately without graceful close.

For complete module, type, and function details, use the [API reference](/reference/).
