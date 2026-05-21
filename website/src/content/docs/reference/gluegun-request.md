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

 Build with `options()` then chain `with_headers` or `add_headers` for
 option-level headers that apply to every call.



## Type aliases

### `Header`

HTTP header represented as `#(name, value)`.

```gleam
pub type Header = #(String, String)
```

### `Stream`

Opaque handle for a Gun request stream.

```gleam
pub type Stream = gluegun/internal.Stream
```

## Functions

### `add_headers`

Add option-level headers that are appended to per-call headers.

```gleam
pub fn add_headers(gluegun/request.RequestOptions, headers: List(#(String, String))) -> gluegun/request.RequestOptions
```

### `cancel`

Cancel an in-flight request stream.

 Sends a reset/cancel to Gun. The connection remains usable for new
 streams. Pending response messages for the cancelled stream may still
 arrive briefly and should be drained.

```gleam
pub fn cancel(gluegun/internal.Connection, gluegun/internal.Stream) -> Result(Nil, gluegun/error.GluegunError)
```

### `data`

Send a chunk of request body data on an open stream.

 Pass `fin.NoFin` for intermediate chunks and `fin.Fin` for the last
 chunk. After sending the final chunk the request body is closed, but the
 stream remains open for response messages.

```gleam
pub fn data(gluegun/internal.Connection, gluegun/internal.Stream, gluegun/fin.Fin, BitArray) -> Result(Nil, gluegun/error.GluegunError)
```

### `flush`

Discard buffered Gun messages currently queued for the calling process.

 Useful after `cancel` or when recovering from an aborted flow. Returns
 `Ok(Nil)` even when no messages were buffered.

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

 Returns a stream reference; response messages are delivered asynchronously
 to the calling process (unless Gun options redirect replies). Use
 `gluegun/message.await` / `await_body` to consume them, or use
 `gluegun/client` helpers to collect a regular response.

 Errors: `ConnectionDown`, `StreamError`, `InvalidOptions`.

```gleam
pub fn request(gluegun/internal.Connection, gluegun/request.Method, String, List(#(String, String)), BitArray, gluegun/request.RequestOptions) -> Result(gluegun/internal.Stream, gluegun/error.GluegunError)
```

### `start_stream`

Start a low-level HTTP request whose body will be streamed in chunks.

 Send zero or more body chunks with `data(..., fin.NoFin, ...)`, then
 terminate the request with a final `data(..., fin.Fin, ...)` (which may
 carry an empty `BitArray` if there is no trailing payload). The stream
 remains open for response messages either way.

 Gun response messages are delivered to the calling process by default;
 pass an option to redirect via Gun's `reply_to` if you need another
 process to consume them.

 Errors: `ConnectionDown`, `StreamError`, `InvalidOptions`.

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
