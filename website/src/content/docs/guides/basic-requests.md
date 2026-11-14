---
title: Basic Requests
description: Use gluegun/client to send one request and collect one response.
---

Use `gluegun/client` to send an HTTP request on an open connection and collect the full response in memory. The result includes status, headers, body, trailers, and all `1xx` informational responses.

<nav class="gg-lifecycle" aria-label="Request lifecycle">
  <ol>
    <li><a href="/installation/">Install</a></li>
    <li>Connect + await</li>
    <li aria-current="step">Request + response</li>
    <li>Close</li>
  </ol>
</nav>

## Builder API

```gleam
import gleam/http
import gluegun/client

fn fetch_json(conn, path, timeout) {
  client.new(http.Get, path)
  |> client.with_header(
    name: "accept",
    value: "application/json",
  )
  |> client.with_timeout(
    timeout: timeout,
  )
  |> client.send(
    connection: conn,
  )
}
```

The connection determines the scheme, host, and port. Pass an encoded request
target such as `/items?tag=a%2Fb&tag=c`; Gluegun sends it without encoding the
path or query again. Bodies must be byte-aligned `BitArray` values, with no
UTF-8 requirement. `client.with_timeout` sets one total budget for dispatch
and response collection; informational responses and body chunks do not restart it.

Gluegun retains this custom request type to avoid repeating the connection's
destination. Standard `gleam/http/request.Request` values and converter
functions are not part of this API.

## Headers

Add request headers with `client.with_header`:

```gleam
import gleam/http
client.new(http.Get, "/api/items")
|> client.with_header(name: "accept", value: "application/json")
|> client.with_header(name: "user-agent", value: "my-app")
|> client.send(connection: conn)
```

Gluegun normalizes header names before it sends them to Gun. Header values do not change.

## One-shot functions

`gluegun/client` has one function for each HTTP method. Use these when you do
not add headers one by one. Each function accepts `connection`, `path`,
`headers`, and a `Timeout`. Methods with bodies also accept a `BitArray` body.

```gleam
import gleam/result
import gluegun/client
import gluegun/connection

pub fn examples(conn) {
  use timeout <- result.try(connection.milliseconds(5000))

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

`client.options` sends `OPTIONS`. See the [client reference](/reference/gluegun-client/) for the full list.

## Examine responses

`client.send` returns a `gluegun/response.Response(BitArray)`. Its `response`
field is a standard `gleam/http/response.Response(BitArray)`. Trailers and
ordered `1xx` informational responses remain alongside it:

```gleam
import gleam/http/response as http_response
import gluegun/response

pub fn handle(res: response.Response(BitArray)) {
  let _status = res.response.status
  let _headers = res.response.headers
  let _content_type = http_response.get_header(res.response, "content-type")
  let _trailers = res.trailers
  let _early_hints = res.informational
  case response.body_text(res) {
    Ok(text) -> text
    Error(_) -> "<binary body>"
  }
}
```

Use `response.body_text` for UTF-8 responses. Use `response.body` for raw bytes.

Standard response helpers work on `res.response`. Keep the outer value when
you transform the body:

```gleam
import gleam/bit_array
import gleam/http/response as http_response
import gleam/result
import gluegun/response

pub fn decode_body(collected: response.Response(BitArray)) {
  use decoded <- result.try(
    http_response.try_map(collected.response, bit_array.to_string),
  )
  Ok(response.Response(..collected, response: decoded))
}
```

The result contains a `Response(String)` with the same trailers and
informational responses. Each informational response is a standard
`gleam/http/response.Response(Nil)` with no body. Selecting only
`collected.response` excludes the supplemental metadata. Trailers never
merge into final headers.

## When to use the client functions

Use `gluegun/client` for:

- GET, POST, PUT, PATCH, DELETE, HEAD, and OPTIONS requests that return HTTP responses.
- Responses that can be collected in memory.
- Applications that already control the Gun connection lifecycle.

Use `gluegun/request` and `gluegun/message` for streamed response chunks, trailers as they arrive, cancellation, flow control, upgrades, or HTTP/2 push.

## Collection failures

The client helpers attempt to cancel a failed stream and drain its queued messages after a timeout, invalid message, or receive failure. They return the original error, keep the connection open, and preserve other streams. Cleanup failures produce a warning.

Cancellation is asynchronous. The drain does not wait for Gun to process cancellation or for future messages. Messages in transit can arrive after the helper returns. The high-level API does not return the failed stream handle; use the low-level API in a separate receiving process if you need strict mailbox isolation.

See the [client reference](/reference/gluegun-client/) for all high-level client functions.
