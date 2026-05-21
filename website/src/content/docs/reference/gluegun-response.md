---
title: gluegun/response
description: HTTP response values collected by `gluegun/client`.
---

# `gluegun/response`

HTTP response values collected by `gluegun/client`.

 A response contains the final status, headers, full body, trailers, and any
 informational `1xx` responses seen before the final response.

## Types

### `Informational`

Informational `1xx` response represented by status and headers.

```gleam
pub type Informational {
  Informational(
    status: Int,
    headers: List(#(String, String))
  )
}
```

### `Response`

Full HTTP response collected from a Gun stream.

 Accessors: `status`, `headers`, `body`, `body_text`, `trailers`,
 `informational`. The body is held fully in memory.

```gleam
pub type Response
```

## Functions

### `body`

Return the full collected response body.

```gleam
pub fn body(Response) -> BitArray
```

### `body_text`

Decode the collected response body as UTF-8 text.

 Returns `DecodeError("Response body is not valid UTF-8")` if the bytes
 are not valid UTF-8. For binary responses use `body` directly.

```gleam
pub fn body_text(Response) -> Result(String, error.GluegunError)
```

### `headers`

Return final response headers.

```gleam
pub fn headers(Response) -> List(#(String, String))
```

### `informational`

Return informational `1xx` responses received before the final response.

```gleam
pub fn informational(Response) -> List(Informational)
```

### `status`

Return the final response status.

```gleam
pub fn status(Response) -> Int
```

### `trailers`

Return response trailers.

```gleam
pub fn trailers(Response) -> List(#(String, String))
```
