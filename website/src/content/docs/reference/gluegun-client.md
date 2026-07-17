---
title: gluegun/client
description: High-level HTTP helpers for existing Gun connections.
---

High-level HTTP helpers for existing Gun connections.

 These helpers collect a full HTTP/1.1 or HTTP/2 response — status,
 headers, body, trailers, and any informational `1xx` responses — into a
 `response.Response`. The body is held fully in memory; use the lower-level
 `gluegun/request` and `gluegun/message` APIs for streaming or very large
 responses.

 Protocol messages for server push, upgrades, and WebSockets are rejected
 with `InvalidMessage`. Use the lower-level `gluegun/message` API for
 those flows.

## Types

### `Request`

A buildable HTTP request: method, path, headers, body, options, and timeout.

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
) -> Result(response.Response, error.GluegunError)
```

### `get`

Send GET on an open connection and collect the full response.

```gleam
pub fn get(
  internal.Connection,
  String,
  List(#(String, String)),
  connection.Timeout
) -> Result(response.Response, error.GluegunError)
```

### `head`

Send HEAD on an open connection and collect the full response.

```gleam
pub fn head(
  internal.Connection,
  String,
  List(#(String, String)),
  connection.Timeout
) -> Result(response.Response, error.GluegunError)
```

### `new`

Start a new `Request` builder with the given method and path.

```gleam
pub fn new(
  request.Method,
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
) -> Result(response.Response, error.GluegunError)
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
) -> Result(response.Response, error.GluegunError)
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
) -> Result(response.Response, error.GluegunError)
```

### `request_options`

Send OPTIONS on an open connection and collect the full response.

```gleam
pub fn request_options(
  internal.Connection,
  String,
  List(#(String, String)),
  connection.Timeout
) -> Result(response.Response, error.GluegunError)
```

### `send`

Send a built `Request` on an open connection and collect the response.

```gleam
pub fn send(
  Request,
  connection: internal.Connection
) -> Result(response.Response, error.GluegunError)
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

```gleam
pub fn with_timeout(
  Request,
  timeout: connection.Timeout
) -> Request
```
