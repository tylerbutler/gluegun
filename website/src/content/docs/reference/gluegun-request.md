---
title: gluegun/request
description: Low-level HTTP request and stream operations.
---

# `gluegun/request`

Low-level HTTP request and stream operations.

 Use this module when you need Gun stream references, chunked request
 bodies, flow-control updates, cancellation, or direct access to asynchronous
 Gun messages. For simple full-body responses, prefer `gluegun/client`.

## Types

### `Method`

HTTP request method constructors.

 Use canonical constructors such as `Get`, `Post`, and `Put`, or `Custom`
 for extension methods.

- `Get()`
- `Head()`
- `Post()`
- `Put()`
- `Patch()`
- `Delete()`
- `Options()`
- `Trace()`
- `Connect()`
- `Custom(String)`

### `RequestOptions`

Request options passed through the low-level request API.



## Type aliases

### `Header`

HTTP header represented as `#(name, value)`.

```gleam
pub type Header = Unknown
```

### `Stream`

Opaque handle for a Gun request stream.

```gleam
pub type Stream = Unknown
```

## Functions

### `add_headers`

Add option-level headers that are appended to per-call headers.

```gleam
pub fn add_headers(gluegun/request.RequestOptions, headers: List(#(String, String))) -> gluegun/request.RequestOptions
```

### `cancel`

Cancel a request stream.

```gleam
pub fn cancel(gluegun/internal.Connection, gluegun/internal.Stream) -> Result(Nil, gluegun/error.GluegunError)
```

### `data`

Stream request body data for a request.

```gleam
pub fn data(gluegun/internal.Connection, gluegun/internal.Stream, gluegun/fin.Fin, BitArray) -> Result(Nil, gluegun/error.GluegunError)
```

### `flush`

Flush Gun messages for a connection.

```gleam
pub fn flush(gluegun/internal.Connection) -> Result(Nil, gluegun/error.GluegunError)
```

### `method_to_string`

Convert a method constructor to its HTTP method string.

```gleam
pub fn method_to_string(gluegun/request.Method) -> String
```

### `options`

Construct default request options.

```gleam
pub fn options() -> gluegun/request.RequestOptions
```

### `request`

Send a low-level HTTP request on an open Gun connection.

 This returns a stream reference. Use `gluegun/client` helpers to collect a
 regular HTTP response into a `Response`.

```gleam
pub fn request(gluegun/internal.Connection, gluegun/request.Method, String, List(#(String, String)), BitArray, gluegun/request.RequestOptions) -> Result(gluegun/internal.Stream, gluegun/error.GluegunError)
```

### `start_stream`

Start a low-level HTTP request whose body will be streamed later.

 The caller must send request body chunks with `data(..., fin.NoFin, ...)` and
 complete the request with `data(..., fin.Fin, ...)`. Gun response messages go to
 the calling process by default unless Gun request options redirect replies.

```gleam
pub fn start_stream(gluegun/internal.Connection, gluegun/request.Method, String, List(#(String, String)), gluegun/request.RequestOptions) -> Result(gluegun/internal.Stream, gluegun/error.GluegunError)
```

### `update_flow`

Update HTTP/1.1 or HTTP/2 stream flow control by the given increment.

 The increment must be positive. Gun rejects non-positive flow-control
 increments, so this function validates the value before crossing the FFI
 boundary and returns `InvalidOptions` for zero or negative increments.

```gleam
pub fn update_flow(gluegun/internal.Connection, gluegun/internal.Stream, Int) -> Result(Nil, gluegun/error.GluegunError)
```

### `with_headers`

Replace option-level headers.

```gleam
pub fn with_headers(gluegun/request.RequestOptions, headers: List(#(String, String))) -> gluegun/request.RequestOptions
```
