//// HTTP response values collected by `gluegun/client`.
////
//// A response contains the final status, headers, full body, trailers, and any
//// informational `1xx` responses seen before the final response.

import gleam/bit_array
import gleam/result
import gluegun/error
import gluegun/request.{type Header}

/// Informational `1xx` response represented by status and headers.
pub type Informational {
  Informational(status: Int, headers: List(Header))
}

/// Full HTTP response collected from a Gun stream.
///
/// Accessors: `status`, `headers`, `body`, `body_text`, `trailers`,
/// `informational`. The body is held fully in memory.
pub opaque type Response {
  Response(
    status: Int,
    headers: List(Header),
    body: BitArray,
    trailers: List(Header),
    informational: List(Informational),
  )
}

/// Return the final response status.
pub fn status(response: Response) -> Int {
  response.status
}

/// Return final response headers.
pub fn headers(response: Response) -> List(Header) {
  response.headers
}

/// Return the full collected response body.
pub fn body(response: Response) -> BitArray {
  response.body
}

/// Return response trailers.
pub fn trailers(response: Response) -> List(Header) {
  response.trailers
}

/// Return informational `1xx` responses received before the final response.
pub fn informational(response: Response) -> List(Informational) {
  response.informational
}

/// Construct a response without informational responses.
@internal
pub fn new(
  status status: Int,
  headers headers: List(Header),
  body body: BitArray,
  trailers trailers: List(Header),
) -> Response {
  Response(
    status: status,
    headers: headers,
    body: body,
    trailers: trailers,
    informational: [],
  )
}

/// Return a response with a replaced body.
@internal
pub fn with_body(response: Response, body body: BitArray) -> Response {
  Response(..response, body: body)
}

/// Return a response with replaced trailers.
@internal
pub fn with_trailers(
  response: Response,
  trailers trailers: List(Header),
) -> Response {
  Response(..response, trailers: trailers)
}

/// Return a response with replaced informational responses.
@internal
pub fn with_informational(
  response: Response,
  informational informational: List(Informational),
) -> Response {
  Response(..response, informational: informational)
}

/// Decode the collected response body as UTF-8 text.
///
/// Returns `DecodeError("Response body is not valid UTF-8")` if the bytes
/// are not valid UTF-8. For binary responses use `body` directly.
pub fn body_text(response: Response) -> Result(String, error.GluegunError) {
  response.body
  |> bit_array.to_string
  |> result.map_error(fn(_) {
    error.DecodeError("Response body is not valid UTF-8")
  })
}
