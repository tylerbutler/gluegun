import gleam/http
import gluegun/connection
import gluegun/error
import gluegun/request
import gluegun/websocket

// Each payload/entry-point combination is a separately selectable Unitest test.
// U+212A lowercases to ASCII "k": validating only after lowercase is unsafe.
pub fn request_per_call_rejects_kelvin_test() {
  reject_request("\u{212A}", False)
}

pub fn request_later_header_rejects_kelvin_test() {
  reject_request("\u{212A}", True)
}

pub fn start_stream_per_call_rejects_kelvin_test() {
  reject_headers("\u{212A}", False)
}

pub fn start_stream_later_header_rejects_kelvin_test() {
  reject_headers("\u{212A}", True)
}

pub fn websocket_upgrade_rejects_kelvin_test() {
  reject_upgrade("\u{212A}")
}

pub fn request_per_call_rejects_embedded_kelvin_test() {
  reject_request("X-\u{212A}ey", False)
}

pub fn request_later_header_rejects_embedded_kelvin_test() {
  reject_request("X-\u{212A}ey", True)
}

pub fn start_stream_per_call_rejects_embedded_kelvin_test() {
  reject_headers("X-\u{212A}ey", False)
}

pub fn start_stream_later_header_rejects_embedded_kelvin_test() {
  reject_headers("X-\u{212A}ey", True)
}

pub fn websocket_upgrade_rejects_embedded_kelvin_test() {
  reject_upgrade("X-\u{212A}ey")
}

pub fn request_per_call_rejects_accented_name_test() {
  reject_request("X-\u{00C9}", False)
}

pub fn request_later_header_rejects_accented_name_test() {
  reject_request("X-\u{00C9}", True)
}

pub fn start_stream_per_call_rejects_accented_name_test() {
  reject_headers("X-\u{00C9}", False)
}

pub fn start_stream_later_header_rejects_accented_name_test() {
  reject_headers("X-\u{00C9}", True)
}

pub fn websocket_upgrade_rejects_accented_name_test() {
  reject_upgrade("X-\u{00C9}")
}

pub fn request_per_call_rejects_long_s_test() {
  reject_request("X-\u{017F}", False)
}

pub fn request_later_header_rejects_long_s_test() {
  reject_request("X-\u{017F}", True)
}

pub fn start_stream_per_call_rejects_long_s_test() {
  reject_headers("X-\u{017F}", False)
}

pub fn start_stream_later_header_rejects_long_s_test() {
  reject_headers("X-\u{017F}", True)
}

pub fn websocket_upgrade_rejects_long_s_test() {
  reject_upgrade("X-\u{017F}")
}

fn reject_request(name: String, later_entry: Bool) -> Nil {
  let #(headers, options) = rejection_headers(name, later_entry)
  request.request(
    current_connection(),
    http.Post,
    "/upload",
    headers,
    <<"body":utf8>>,
    options,
  )
  |> assert_rejected
}

fn reject_headers(name: String, later_entry: Bool) -> Nil {
  let #(headers, options) = rejection_headers(name, later_entry)
  request.start_stream(
    current_connection(),
    http.Post,
    "/upload",
    headers,
    options,
  )
  |> assert_rejected
}

fn reject_upgrade(name: String) -> Nil {
  websocket.upgrade(
    current_connection(),
    connection.Http1,
    "/ws",
    [
      #("X-Valid", "first"),
      #(name, "unchanged"),
    ],
    websocket.upgrade_options(),
  )
  |> assert_rejected
}

fn rejection_headers(
  name: String,
  later_entry: Bool,
) -> #(List(request.Header), request.RequestOptions) {
  case later_entry {
    False -> #([#("X-Valid", "first"), #(name, "unchanged")], request.options())
    True -> #(
      [#("X-Valid", "first"), #("X-Later", "second"), #(name, "unchanged")],
      request.options(),
    )
  }
}

fn assert_rejected(actual: Result(request.Stream, error.GluegunError)) -> Nil {
  // Check and drain casts even when the API incorrectly returned success.
  let cast = has_outgoing_cast()
  let expected = Error(error.InvalidOptions("Request(InvalidHeaderName)"))
  let assert #(True, _, _) = #(actual == expected, actual, expected)
  let assert False = cast
  Nil
}

// All RFC tchar punctuation, mixed case, digits, duplicate-name order, empty
// values, HTAB, and Unicode values must survive the successful outbound path.
fn per_call_headers() -> List(request.Header) {
  [
    #("X-MiXeD", " \tMiXeD \u{212A}\u{00E9}\u{1F642}\t "),
    #("AZaz09!#$%&'*+-.^_`|~", "Punctuation"),
    #("x-MIXED", "\tSecond \u{212A}\u{00E9}\t"),
    #("X-Empty", ""),
  ]
}

fn expected_headers() -> List(request.Header) {
  [
    #("x-mixed", " \tMiXeD \u{212A}\u{00E9}\u{1F642}\t "),
    #("azaz09!#$%&'*+-.^_`|~", "Punctuation"),
    #("x-mixed", "\tSecond \u{212A}\u{00E9}\t"),
    #("x-empty", ""),
  ]
}

pub fn request_preserves_normalized_headers_order_and_values_test() -> Nil {
  let body = <<"body":utf8>>
  let assert Ok(stream) =
    request.request(
      current_connection(),
      http.Other("MiXeD"),
      "/upload?Case=Keep",
      per_call_headers(),
      body,
      request.options(),
    )
  let actual = capture_request(stream)
  let expected = Ok(#("MiXeD", "/upload?Case=Keep", expected_headers(), body))
  let assert #(True, _, _) = #(actual == expected, actual, expected)
  let assert False = has_outgoing_cast()
  Nil
}

pub fn start_stream_preserves_normalized_headers_order_and_values_test() -> Nil {
  let assert Ok(stream) =
    request.start_stream(
      current_connection(),
      http.Other("MiXeD"),
      "/upload?Case=Keep",
      per_call_headers(),
      request.options(),
    )
  let actual = capture_headers(stream)
  let expected = Ok(#("MiXeD", "/upload?Case=Keep", expected_headers()))
  let assert #(True, _, _) = #(actual == expected, actual, expected)
  let assert False = has_outgoing_cast()
  Nil
}

pub fn websocket_upgrade_preserves_normalized_headers_and_values_test() -> Nil {
  let assert Ok(stream) =
    websocket.upgrade(
      current_connection(),
      connection.Http1,
      "/ws?Case=Keep",
      per_call_headers(),
      websocket.upgrade_options(),
    )
  assert_upgrade(stream)
}

fn assert_upgrade(stream: request.Stream) -> Nil {
  let actual = capture_ws_upgrade(stream)
  let expected = Ok(#("/ws?Case=Keep", expected_headers()))
  let assert #(True, _, _) = #(actual == expected, actual, expected)
  let assert False = has_outgoing_cast()
  Nil
}

@external(erlang, "gluegun_ffi_test", "current_connection")
fn current_connection() -> connection.Connection

@external(erlang, "gluegun_outgoing_headers_test", "capture_request")
fn capture_request(
  stream: request.Stream,
) -> Result(#(String, String, List(request.Header), BitArray), Nil)

@external(erlang, "gluegun_outgoing_headers_test", "capture_headers")
fn capture_headers(
  stream: request.Stream,
) -> Result(#(String, String, List(request.Header)), Nil)

@external(erlang, "gluegun_outgoing_headers_test", "capture_ws_upgrade")
fn capture_ws_upgrade(
  stream: request.Stream,
) -> Result(#(String, List(request.Header)), Nil)

@external(erlang, "gluegun_outgoing_headers_test", "has_outgoing_cast")
fn has_outgoing_cast() -> Bool
