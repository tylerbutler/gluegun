import gleam/bit_array
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gluegun/connection
import gluegun/request.{type Header}

pub fn format(
  protocol protocol: connection.Protocol,
  status status: Int,
  headers headers: List(Header),
  body body: BitArray,
  body_preview_bytes body_preview_bytes: Int,
) -> String {
  "protocol: "
  <> protocol_name(protocol)
  <> "\nstatus: "
  <> int.to_string(status)
  <> "\n"
  <> format_headers(headers)
  <> "body-preview: "
  <> body_preview(body, body_preview_bytes)
  <> "\n"
}

pub fn protocol_name(protocol: connection.Protocol) -> String {
  case protocol {
    connection.Http1 -> "HTTP/1.1"
    connection.Http2 -> "HTTP/2"
  }
}

fn format_headers(headers: List(Header)) -> String {
  case headers {
    [] -> "headers: none\n"
    _ ->
      "headers:\n"
      <> string.concat(
        list.map(headers, fn(header) {
          let #(name, value) = header
          "  " <> name <> ": " <> value <> "\n"
        }),
      )
  }
}

fn body_preview(body: BitArray, max_bytes: Int) -> String {
  let bytes = bit_array.byte_size(body)
  let length = int.min(bytes, max_bytes)
  let preview =
    bit_array.slice(body, at: 0, take: length)
    |> result.unwrap(<<>>)

  case bit_array.to_string(preview) {
    Ok(text) -> text
    Error(_) -> bit_array.inspect(preview)
  }
}
