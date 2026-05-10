//// HTTP response values collected by `gluegun/client`.
////
//// A response contains the final status, headers, full body, trailers, and any
//// informational `1xx` responses seen before the final response.

import gleam/bit_array
import gleam/result
import gluegun/error
import gluegun/request.{type Header}

/// Informational `1xx` response represented by status and headers.
pub type Informational =
  #(Int, List(Header))

/// Full HTTP response collected from a Gun stream.
pub type Response {
  Response(
    status: Int,
    headers: List(Header),
    body: BitArray,
    trailers: List(Header),
    informational: List(Informational),
  )
}

/// Construct a response without informational responses.
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
pub fn with_body(response: Response, body body: BitArray) -> Response {
  Response(..response, body: body)
}

/// Return a response with replaced trailers.
pub fn with_trailers(
  response: Response,
  trailers trailers: List(Header),
) -> Response {
  Response(..response, trailers: trailers)
}

/// Return a response with replaced informational responses.
pub fn with_informational(
  response: Response,
  informational informational: List(Informational),
) -> Response {
  Response(..response, informational: informational)
}

/// Decode a response body as UTF-8 text.
pub fn body_text(response: Response) -> Result(String, error.GluegunError) {
  response.body
  |> bit_array.to_string
  |> result.map_error(fn(_) {
    error.DecodeError("Response body is not valid UTF-8")
  })
}
