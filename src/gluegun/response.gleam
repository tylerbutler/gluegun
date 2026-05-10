import gleam/bit_array
import gleam/result
import gluegun/error
import gluegun/request.{type Header}

pub type Informational =
  #(Int, List(Header))

pub type Response {
  Response(
    status: Int,
    headers: List(Header),
    body: BitArray,
    trailers: List(Header),
    informational: List(Informational),
  )
}

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

pub fn with_body(response: Response, body body: BitArray) -> Response {
  Response(..response, body: body)
}

pub fn with_trailers(
  response: Response,
  trailers trailers: List(Header),
) -> Response {
  Response(..response, trailers: trailers)
}

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
