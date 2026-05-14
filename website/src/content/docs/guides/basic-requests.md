---
title: Basic Requests
description: Use gluegun/client to send one request and collect one response.
---

Use `gluegun/client` when you want to send one regular HTTP request on an existing connection and collect the full response body in memory.

```gleam
import gluegun/client
import gluegun/request

fn fetch_json(conn, path, timeout) {
  client.new(request.Get, path)
  |> client.with_header(name: "accept", value: "application/json")
  |> client.with_timeout(timeout: timeout)
  |> client.send(connection: conn)
}
```

## When to use the client helpers

Use `gluegun/client` for:

- GET, POST, PUT, PATCH, DELETE, HEAD, and OPTIONS requests with regular responses.
- Responses where collecting the body in memory is acceptable.
- Applications that already manage a Gun connection lifecycle.

Use `gluegun/request` and `gluegun/message` instead when you need streamed response chunks, trailers as they arrive, cancellation, flow control, upgrades, or HTTP/2 push.

## Headers

Add request headers with `client.with_header`:

```gleam
client.new(request.Get, "/api/items")
|> client.with_header(name: "accept", value: "application/json")
|> client.with_header(name: "user-agent", value: "my-app")
|> client.send(connection: conn)
```

Header names are normalized before crossing the Gun boundary. Header values are preserved.
