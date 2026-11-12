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
 and drain its queued messages, then return the original error. They also
 cancel and drain each promised stream found in a rejected or queued push.
 They keep other streams and the connection open. Cancellation is asynchronous:
 messages in transit can arrive after the drain. For strict mailbox
 isolation, use the low-level API in a separate receiving process.

## Types

### `Request`

A connection-bound request: method, path, headers, body, and total timeout.

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
  path: String,
  headers: List(#(String, String)),
  timeout: connection.Timeout
) -> Result(response.Response(BitArray), error.GluegunError)
```

### `get`

Send GET on an open connection and collect the full response.

```gleam
pub fn get(
  internal.Connection,
  path: String,
  headers: List(#(String, String)),
  timeout: connection.Timeout
) -> Result(response.Response(BitArray), error.GluegunError)
```

### `head`

Send HEAD on an open connection and collect the full response.

```gleam
pub fn head(
  internal.Connection,
  path: String,
  headers: List(#(String, String)),
  timeout: connection.Timeout
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

### `options`

Send OPTIONS on an open connection and collect the full response.

```gleam
pub fn options(
  internal.Connection,
  path: String,
  headers: List(#(String, String)),
  timeout: connection.Timeout
) -> Result(response.Response(BitArray), error.GluegunError)
```

### `patch`

Send PATCH on an open connection and collect the full response.

```gleam
pub fn patch(
  internal.Connection,
  path: String,
  headers: List(#(String, String)),
  body: BitArray,
  timeout: connection.Timeout
) -> Result(response.Response(BitArray), error.GluegunError)
```

### `post`

Send POST on an open connection and collect the full response.

```gleam
pub fn post(
  internal.Connection,
  path: String,
  headers: List(#(String, String)),
  body: BitArray,
  timeout: connection.Timeout
) -> Result(response.Response(BitArray), error.GluegunError)
```

### `put`

Send PUT on an open connection and collect the full response.

```gleam
pub fn put(
  internal.Connection,
  path: String,
  headers: List(#(String, String)),
  body: BitArray,
  timeout: connection.Timeout
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

### `with_timeout`

Set the total request budget, including dispatch and all response messages.

 Informational responses and body chunks do not restart the budget.
 `Infinity` has no limit. Collection still keeps the complete body in memory.

```gleam
pub fn with_timeout(
  Request,
  timeout: connection.Timeout
) -> Request
```
