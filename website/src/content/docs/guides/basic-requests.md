---
title: Basic Requests
description: Use gluegun/client to send one request and collect one response.
---

Use `gluegun/client` to send one usual HTTP request on an open connection. The client collects the full response in memory: status, headers, body, trailers, and all `1xx` informational responses.

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

## One-shot functions

`gluegun/client` has one function for each HTTP method. Use these when you do
not add headers one by one. Each function accepts `connection`, `path`,
`headers`, and a `Timeout`. Methods with bodies also accept a `BitArray` body.

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

`client.request_options` sends `OPTIONS`. See the [client reference](/reference/gluegun-client/) for the full list.

## Examine responses

`client.send` returns a `response.Response`. It holds the final status, headers, body, trailers, and all `1xx` informational responses that came before the final response:

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

Use `response.body_text` for UTF-8 responses. Use `response.body` for raw bytes.

## When to use the client functions

Use `gluegun/client` for:

- GET, POST, PUT, PATCH, DELETE, HEAD, and OPTIONS requests with usual responses.
- Responses that can be collected in memory.
- Applications that already control the Gun connection lifecycle.

Use `gluegun/request` and `gluegun/message` for streamed response chunks, trailers as they arrive, cancellation, flow control, upgrades, or HTTP/2 push.

## Headers

Add request headers with `client.with_header`:

```gleam
client.new(request.Get, "/api/items")
|> client.with_header(name: "accept", value: "application/json")
|> client.with_header(name: "user-agent", value: "my-app")
|> client.send(connection: conn)
```

Gluegun normalizes header names before it sends them to Gun. Header values do not change.

See the [client reference](/reference/gluegun-client/) for all high-level client functions.
