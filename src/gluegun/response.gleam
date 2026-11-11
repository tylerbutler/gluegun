//// HTTP response values collected by `gluegun/client`.
////
//// The `response` field is a standard `gleam/http/response.Response`.
//// Trailers and ordered informational `1xx` responses remain alongside it.
//// Selecting only `response` excludes that metadata; keep the outer value
//// when you need the complete exchange.
////
//// Import `gleam/http/response as http_response` for standard response helpers.

import gleam/bit_array
import gleam/http/response as http_response
import gleam/result
import gluegun/error
import gluegun/request.{type Header}

/// A standard informational `1xx` response with no body.
pub type Informational =
  http_response.Response(Nil)

/// Full HTTP response collected from a Gun stream.
///
/// The client collects a `Response(BitArray)` with the full body in memory.
/// Use standard response helpers on `response`, then update that field to keep
/// trailers and informational responses when transforming the body.
pub type Response(body) {
  Response(
    response: http_response.Response(body),
    trailers: List(Header),
    informational: List(Informational),
  )
}

/// Return the final response status.
pub fn status(response: Response(body)) -> Int {
  response.response.status
}

/// Return final response headers.
pub fn headers(response: Response(body)) -> List(Header) {
  response.response.headers
}

/// Return the full collected response body.
pub fn body(response: Response(body)) -> body {
  response.response.body
}

/// Return response trailers.
pub fn trailers(response: Response(body)) -> List(Header) {
  response.trailers
}

/// Return informational `1xx` responses received before the final response.
pub fn informational(response: Response(body)) -> List(Informational) {
  response.informational
}

/// Construct a response without informational responses.
@internal
pub fn new(
  status status: Int,
  headers headers: List(Header),
  body body: body,
  trailers trailers: List(Header),
) -> Response(body) {
  Response(
    response: http_response.Response(
      status: status,
      headers: headers,
      body: body,
    ),
    trailers: trailers,
    informational: [],
  )
}

/// Return a response with a replaced body. Primarily used by `gluegun/client`
/// while collecting a response and by tests that build deterministic values.
@internal
pub fn with_body(
  response: Response(old_body),
  body body: new_body,
) -> Response(new_body) {
  Response(
    ..response,
    response: http_response.set_body(response.response, body),
  )
}

/// Return a response with replaced trailers. Primarily used by
/// `gluegun/client` when a collected response ends with trailer fields.
@internal
pub fn with_trailers(
  response: Response(body),
  trailers trailers: List(Header),
) -> Response(body) {
  Response(..response, trailers: trailers)
}

/// Return a response with replaced informational responses. Primarily used by
/// `gluegun/client` to preserve `1xx` responses seen before the final response.
@internal
pub fn with_informational(
  response: Response(body),
  informational informational: List(Informational),
) -> Response(body) {
  Response(..response, informational: informational)
}

/// Decode the collected response body as UTF-8 text.
///
/// Returns `DecodeError("Response body is not valid UTF-8")` if the bytes
/// are not valid UTF-8. For binary responses use `body` directly.
pub fn body_text(
  response: Response(BitArray),
) -> Result(String, error.GluegunError) {
  response.response.body
  |> bit_array.to_string
  |> result.map_error(fn(_) {
    error.DecodeError("Response body is not valid UTF-8")
  })
}
