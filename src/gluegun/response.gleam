import gluegun/request.{type Header}

pub type Response {
  Response(
    status: Int,
    headers: List(Header),
    body: BitArray,
    trailers: List(Header),
  )
}

pub fn new(
  status status: Int,
  headers headers: List(Header),
  body body: BitArray,
  trailers trailers: List(Header),
) -> Response {
  Response(status: status, headers: headers, body: body, trailers: trailers)
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
