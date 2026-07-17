---
title: Basic Requests
description: Use gluegun/client to send one request and collect one response.
---

Use `gluegun/client` when you want to send one regular HTTP request on an existing connection and collect the full response — status, headers, body, trailers, and any informational `1xx` responses — in memory.

## Builder API

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

## One-shot helpers

For requests that do not need extra header chaining, `gluegun/client` ships
per-method helpers. Each takes `connection`, `path`, `headers`, and a
`Timeout`; methods with bodies also take a `BitArray` body.

```gleam
import gluegun/client
import gluegun/connection

pub fn examples(conn) {
  let timeout = connection.Milliseconds(5000)

  let _ = client.get(conn, "/items", [], timeout)
  let _ = client.head(conn, "/items/1", [], timeout)
  let _ = client.delete(conn, "/items/1", [], timeout)

  let json = <<"{\"name\":\"new\"}":utf8>>
  let headers = [#("content-type", "application/json")]

  let _ = client.post(conn, "/items", headers, json, timeout)
  let _ = client.put(conn, "/items/1", headers, json, timeout)
  let _ = client.patch(conn, "/items/1", headers, json, timeout)
}
```

`client.request_options` covers `OPTIONS`. See the [client reference](/reference/gluegun-client/) for the full list.

## Inspecting responses

`client.send` returns a `response.Response` that carries the final status, headers, body, trailers, and any `1xx` informational responses seen before the final response:

```gleam
import gluegun/response

pub fn handle(res) {
  let _status = response.status(res)
  let _headers = response.headers(res)
  let _trailers = response.trailers(res)
  let _early_hints = response.informational(res)
  case response.body_text(res) {
    Ok(text) -> text
    Error(_) -> "<binary body>"
  }
}
```

Use `response.body_text` for UTF-8 responses or `response.body` for raw bytes.

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

See the [client reference](/reference/gluegun-client/) for all high-level client helpers.
