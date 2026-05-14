---
title: gluegun/response
description: HTTP response values collected by `gluegun/client`.
---

# `gluegun/response`

HTTP response values collected by `gluegun/client`.

 A response contains the final status, headers, full body, trailers, and any
 informational `1xx` responses seen before the final response.

## Types

### `Response`

Full HTTP response collected from a Gun stream.



## Type aliases

### `Informational`

Informational `1xx` response represented by status and headers.

```gleam
pub type Informational = Unknown
```

## Functions

### `body`

Return the full collected response body.

```gleam
pub fn body(gluegun/response.Response) -> BitArray
```

### `body_text`

Decode a response body as UTF-8 text.

```gleam
pub fn body_text(gluegun/response.Response) -> Result(String, gluegun/error.GluegunError)
```

### `headers`

Return final response headers.

```gleam
pub fn headers(gluegun/response.Response) -> List(#(String, String))
```

### `informational`

Return informational `1xx` responses received before the final response.

```gleam
pub fn informational(gluegun/response.Response) -> List(#(Int, List(#(String, String))))
```

### `new`

Construct a response without informational responses.

```gleam
pub fn new(status: Int, headers: List(#(String, String)), body: BitArray, trailers: List(#(String, String))) -> gluegun/response.Response
```

### `status`

Return the final response status.

```gleam
pub fn status(gluegun/response.Response) -> Int
```

### `trailers`

Return response trailers.

```gleam
pub fn trailers(gluegun/response.Response) -> List(#(String, String))
```

### `with_body`

Return a response with a replaced body.

```gleam
pub fn with_body(gluegun/response.Response, body: BitArray) -> gluegun/response.Response
```

### `with_informational`

Return a response with replaced informational responses.

```gleam
pub fn with_informational(gluegun/response.Response, informational: List(#(Int, List(#(String, String))))) -> gluegun/response.Response
```

### `with_trailers`

Return a response with replaced trailers.

```gleam
pub fn with_trailers(gluegun/response.Response, trailers: List(#(String, String))) -> gluegun/response.Response
```
