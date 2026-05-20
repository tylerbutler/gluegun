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

- `Informational(Int, List(#(String, String)))`

### `Response`

Full HTTP response collected from a Gun stream.



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
pub fn informational(gluegun/response.Response) -> List(gluegun/response.Informational)
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
