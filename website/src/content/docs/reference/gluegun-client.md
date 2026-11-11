---
title: gluegun/client
description: High-level HTTP helpers for existing Gun connections.
---

High-level HTTP helpers for existing Gun connections.

 These helpers collect a full HTTP/1.1 or HTTP/2 response — status,
 headers, body, trailers, and any informational `1xx` responses — into a
 `response.Response(BitArray)`. Its `response` field is a standard
 `gleam/http/response.Response(BitArray)`. The body is held fully in memory;
 use the lower-level `gluegun/request` and `gluegun/message` APIs for
 streaming or very large responses.

 Protocol messages for server push, upgrades, and WebSockets are rejected
 with `InvalidMessage`. Use the lower-level `gluegun/message` API for
 those flows.

 If collection fails, these helpers attempt to cancel the failed stream
 and drain its queued messages, then return the original error. They keep
 other streams and the connection open. Cancellation is asynchronous:
 messages in transit can arrive after the drain. For strict mailbox
 isolation, use the low-level API in a separate receiving process.

## Types

### `Request`

A connection-bound request: method, path, headers, body, options, and timeout.

 The connection supplied to `send` determines the scheme, host, and port.
 Supply a request target such as `/items?page=2`, not a full URL. Gluegun
 sends the path and query as supplied; it does not percent-encode them.
 The body must contain whole bytes and need not be UTF-8.

 This custom type avoids duplicating the connection's destination fields.
 It does not accept or convert standard `gleam/http/request.Request` values.

```gleam
pub type Request
```

## Functions

### `add_headers`

Append request headers.

```gleam
pub fn add_headers(
  Request,
  headers: List(#(String, String))
) -> Request
```

### `delete`

Send DELETE on an open connection and collect the full response.

```gleam
pub fn delete(
  internal.Connection,
  String,
  List(#(String, String)),
  connection.Timeout
) -> Result(response.Response(BitArray), error.GluegunError)
```

### `get`

Send GET on an open connection and collect the full response.

```gleam
pub fn get(
  internal.Connection,
  String,
  List(#(String, String)),
  connection.Timeout
) -> Result(response.Response(BitArray), error.GluegunError)
```

### `head`

Send HEAD on an open connection and collect the full response.

```gleam
pub fn head(
  internal.Connection,
  String,
  List(#(String, String)),
  connection.Timeout
) -> Result(response.Response(BitArray), error.GluegunError)
```

### `new`

Start a new `Request` builder with the given method and path.

```gleam
pub fn new(
  http.Method,
  String
) -> Request
```

### `patch`

Send PATCH on an open connection and collect the full response.

```gleam
pub fn patch(
  internal.Connection,
  String,
  List(#(String, String)),
  BitArray,
  connection.Timeout
) -> Result(response.Response(BitArray), error.GluegunError)
```

### `post`

Send POST on an open connection and collect the full response.

```gleam
pub fn post(
  internal.Connection,
  String,
  List(#(String, String)),
  BitArray,
  connection.Timeout
) -> Result(response.Response(BitArray), error.GluegunError)
```

### `put`

Send PUT on an open connection and collect the full response.

```gleam
pub fn put(
  internal.Connection,
  String,
  List(#(String, String)),
  BitArray,
  connection.Timeout
) -> Result(response.Response(BitArray), error.GluegunError)
```

### `request_options`

Send OPTIONS on an open connection and collect the full response.

```gleam
pub fn request_options(
  internal.Connection,
  String,
  List(#(String, String)),
  connection.Timeout
) -> Result(response.Response(BitArray), error.GluegunError)
```

### `send`

Send a built `Request` on an open connection and collect the response.

```gleam
pub fn send(
  Request,
  connection: internal.Connection
) -> Result(response.Response(BitArray), error.GluegunError)
```

### `with_body`

Replace the request body.

```gleam
pub fn with_body(
  Request,
  body: BitArray
) -> Request
```

### `with_header`

Append a single request header.

```gleam
pub fn with_header(
  Request,
  name: String,
  value: String
) -> Request
```

### `with_headers`

Replace request headers.

```gleam
pub fn with_headers(
  Request,
  headers: List(#(String, String))
) -> Request
```

### `with_options`

Replace low-level request options.

```gleam
pub fn with_options(
  Request,
  options: request.RequestOptions
) -> Request
```

### `with_timeout`

Replace the request timeout.

 This bounds each response-message wait, not the complete exchange.

```gleam
pub fn with_timeout(
  Request,
  timeout: connection.Timeout
) -> Request
```
