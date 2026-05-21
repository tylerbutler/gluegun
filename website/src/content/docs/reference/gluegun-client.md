---
title: gluegun/client
description: High-level HTTP helpers for existing Gun connections.
---

# `gluegun/client`

High-level HTTP helpers for existing Gun connections.

 These helpers collect regular HTTP/1.1 and HTTP/2 responses into
 `response.Response`.
 Informational `1xx` responses are preserved and can be inspected with
 `response.informational`.
 Protocol messages for server push, upgrades, and WebSockets are rejected with
 `InvalidMessage`; use the lower-level `gluegun/message` API for those flows.
 Full response bodies are collected in memory; use the lower-level APIs for
 streaming or very large responses.

## Types

### `Request`

A collected HTTP request command.



## Functions

### `add_headers`

Append request headers.

```gleam
pub fn add_headers(gluegun/client.Request, headers: List(#(String, String))) -> gluegun/client.Request
```

### `delete`

Send DELETE on an open connection and collect the full response.

```gleam
pub fn delete(gluegun/internal.Connection, String, List(#(String, String)), gluegun/connection.Timeout) -> Result(gluegun/response.Response, gluegun/error.GluegunError)
```

### `get`

Send GET on an open connection and collect the full response.

```gleam
pub fn get(gluegun/internal.Connection, String, List(#(String, String)), gluegun/connection.Timeout) -> Result(gluegun/response.Response, gluegun/error.GluegunError)
```

### `head`

Send HEAD on an open connection and collect the full response.

```gleam
pub fn head(gluegun/internal.Connection, String, List(#(String, String)), gluegun/connection.Timeout) -> Result(gluegun/response.Response, gluegun/error.GluegunError)
```

### `new`

Construct a collected HTTP request command.

```gleam
pub fn new(gluegun/request.Method, String) -> gluegun/client.Request
```

### `patch`

Send PATCH on an open connection and collect the full response.

```gleam
pub fn patch(gluegun/internal.Connection, String, List(#(String, String)), BitArray, gluegun/connection.Timeout) -> Result(gluegun/response.Response, gluegun/error.GluegunError)
```

### `post`

Send POST on an open connection and collect the full response.

```gleam
pub fn post(gluegun/internal.Connection, String, List(#(String, String)), BitArray, gluegun/connection.Timeout) -> Result(gluegun/response.Response, gluegun/error.GluegunError)
```

### `put`

Send PUT on an open connection and collect the full response.

```gleam
pub fn put(gluegun/internal.Connection, String, List(#(String, String)), BitArray, gluegun/connection.Timeout) -> Result(gluegun/response.Response, gluegun/error.GluegunError)
```

### `request_options`

Send OPTIONS on an open connection and collect the full response.

```gleam
pub fn request_options(gluegun/internal.Connection, String, List(#(String, String)), gluegun/connection.Timeout) -> Result(gluegun/response.Response, gluegun/error.GluegunError)
```

### `send`

Send a collected HTTP request command on an open connection.

```gleam
pub fn send(gluegun/client.Request, connection: gluegun/internal.Connection) -> Result(gluegun/response.Response, gluegun/error.GluegunError)
```

### `with_body`

Replace the request body.

```gleam
pub fn with_body(gluegun/client.Request, body: BitArray) -> gluegun/client.Request
```

### `with_header`

Append a single request header.

```gleam
pub fn with_header(gluegun/client.Request, name: String, value: String) -> gluegun/client.Request
```

### `with_headers`

Replace request headers.

```gleam
pub fn with_headers(gluegun/client.Request, headers: List(#(String, String))) -> gluegun/client.Request
```

### `with_options`

Replace low-level request options.

```gleam
pub fn with_options(gluegun/client.Request, options: gluegun/request.RequestOptions) -> gluegun/client.Request
```

### `with_timeout`

Replace the request timeout.

```gleam
pub fn with_timeout(gluegun/client.Request, timeout: gluegun/connection.Timeout) -> gluegun/client.Request
```
