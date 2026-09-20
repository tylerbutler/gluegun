---
title: Quick Start
description: Send a basic GET request with Gluegun.
next:
  link: /guides/basic-requests/
  label: Add headers and bodies
---

Open a Gun connection. Wait until it is ready. Send a GET request. Collect the full response in memory.

Before you start, [install Gluegun](/installation/) and confirm that the package target is `erlang`.

<nav class="gg-lifecycle" aria-label="Request lifecycle">
  <ol>
    <li><a href="/installation/">Install</a></li>
    <li>Connect + await</li>
    <li aria-current="step">Request + response</li>
    <li>Close</li>
  </ol>
</nav>

```gleam
import gleam/int
import gleam/io
import gleam/result
import gluegun/client
import gluegun/connection
import gluegun/request
import gluegun/response

pub fn main() {
  use timeout <- result.try(connection.milliseconds(5000))

  use conn <- result.try(
    connection.open(
      connection.options(),
      host: "example.com",
      port: 80,
    ),
  )
  use _protocol <- result.try(
    connection.await_up(conn, timeout),
  )

  use res <- result.try(
    client.new(request.Get, "/")
    |> client.with_timeout(
      timeout: timeout,
    )
    |> client.send(
      connection: conn,
    ),
  )

  io.println("status: " <> int.to_string(response.status(res)))

  case response.body_text(res) {
    Ok(text) -> io.println(text)
    Error(_) ->
      io.println(
        "response body was not UTF-8",
      )
  }

  connection.close(conn)
}
```

Run the example:

```sh
gleam run
```

You should see `status: 200`, followed by the HTML response from `example.com`.

If the connection does not open or the request times out, use the
[troubleshooting guide](/advanced/troubleshooting/).

## Key idea

Gluegun keeps connection setup and requests separate:

1. Open a connection to a host and port.
2. Wait until Gun reports the negotiated protocol.
3. Send requests with paths such as `/`, `/api/items`, or `/health`.
4. Close or shut down the connection when you are finished.

If you have a full URL, parse it with `gleam/uri` before you call Gluegun. Gluegun accepts only the separate host, port, transport, path, and query values.

`connection.milliseconds(Int)` validates and returns a finite `Timeout`. Use `connection.infinity()` to wait without a limit. The same `Timeout` value applies to connection readiness, request bodies, and message receives.

Use `connection.close` for usual teardown. Use `connection.shutdown` only when a connection seems stuck. `shutdown` stops the Gun process immediately, without a graceful close.

For full module, type, and function details, use the [API reference](/reference/).
