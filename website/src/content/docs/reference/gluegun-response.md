---
title: gluegun/response
description: HTTP response values collected by `gluegun/client`.
---

HTTP response values collected by `gluegun/client`.

 The `response` field is a standard `gleam/http/response.Response`.
 Trailers and ordered informational `1xx` responses remain alongside it.
 Selecting only `response` excludes that metadata; keep the outer value
 when you need the complete exchange.

 Import `gleam/http/response as http_response` for standard response helpers.

## Types

### `Response`

Full HTTP response collected from a Gun stream.

 The client collects a `Response(BitArray)` with the full body in memory.
 Use standard response helpers on `response`, then update that field to keep
 trailers and informational responses when transforming the body.

```gleam
pub type Response(a) {
  Response(
    response: http_response.Response(a),
    trailers: List(#(String, String)),
    informational: List(http_response.Response(Nil))
  )
}
```

## Type aliases

### `Informational`

A standard informational `1xx` response with no body.

```gleam
pub type Informational = http_response.Response(Nil)
```

## Functions

### `body`

Return the full collected response body.

```gleam
pub fn body(Response(a)) -> a
```

### `body_text`

Decode the collected response body as UTF-8 text.

 Returns `DecodeError("Response body is not valid UTF-8")` if the bytes
 are not valid UTF-8. For binary responses use `body` directly.

```gleam
pub fn body_text(Response(BitArray)) -> Result(String, error.GluegunError)
```

### `headers`

Return final response headers.

```gleam
pub fn headers(Response(a)) -> List(#(String, String))
```

### `informational`

Return informational `1xx` responses received before the final response.

```gleam
pub fn informational(Response(a)) -> List(http_response.Response(Nil))
```

### `status`

Return the final response status.

```gleam
pub fn status(Response(a)) -> Int
```

### `trailers`

Return response trailers.

```gleam
pub fn trailers(Response(a)) -> List(#(String, String))
```
