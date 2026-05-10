import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/list
import gleam/result
import gleeunit/should
import gluegun/connection
import gluegun/internal
import gluegun/message

pub fn ffi_timeout_conversion_test() {
  decode.run(
    connection.timeout_to_ffi(connection.Milliseconds(123)),
    decode.int,
  )
  |> should.equal(Ok(123))

  decode.run(connection.timeout_to_ffi(connection.Infinity), atom.decoder())
  |> should.equal(Ok(atom.create("infinity")))
}

pub fn ffi_protocol_ordering_test() {
  connection.connect_options()
  |> connection.with_protocols([connection.Http2, connection.Http1])
  |> connection.options_to_ffi
  |> decode.run(decode.at(["protocols"], decode.list(atom.decoder())))
  |> result.map(list.map(_, atom.to_string))
  |> should.equal(Ok(["http2", "http"]))
}

pub fn ffi_error_timeout_maps_to_error_variant_test() {
  message.decode_ffi_error(atom.to_dynamic(atom.create("timeout")))
  |> should.equal(message.Timeout)
}

pub fn ffi_response_message_shape_decodes_test() {
  gluegun_ffi_test_response()
  |> message.decode
  |> should.equal(
    Ok(message.Response(message.Fin, 200, [#("content-type", "text/plain")])),
  )
}

pub fn ffi_data_message_shape_decodes_binary_body_test() {
  gluegun_ffi_test_data()
  |> message.decode
  |> should.equal(Ok(message.Data(message.NoFin, <<"hello":utf8>>)))
}

pub fn ffi_stream_refs_are_opaque_test() {
  let stream = gluegun_ffi_test_stream_ref()

  internal.stream(stream)
  |> internal.stream_raw
  |> should.equal(stream)
}

@external(erlang, "gluegun_ffi", "test_response_message")
fn gluegun_ffi_test_response() -> dynamic.Dynamic

@external(erlang, "gluegun_ffi", "test_data_message")
fn gluegun_ffi_test_data() -> dynamic.Dynamic

@external(erlang, "gluegun_ffi", "test_stream_ref")
fn gluegun_ffi_test_stream_ref() -> dynamic.Dynamic
