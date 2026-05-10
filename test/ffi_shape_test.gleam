import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/list
import gleam/result
import gleeunit/should
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/internal
import gluegun/internal/ffi_result
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
  connection.options()
  |> connection.with_protocols([connection.Http2, connection.Http1])
  |> connection.options_to_ffi
  |> decode.run(decode.at(["protocols"], decode.list(atom.decoder())))
  |> result.map(list.map(_, atom.to_string))
  |> should.equal(Ok(["http2", "http"]))
}

pub fn ffi_await_up_invalid_protocol_preserves_decode_error_test() {
  connection.decode_await_up_result(Ok(atom.to_dynamic(atom.create("spdy"))))
  |> should.equal(Error(error.DecodeError("Invalid protocol")))
}

pub fn ffi_error_timeout_maps_to_error_variant_test() {
  message.decode_ffi_error(atom.to_dynamic(atom.create("timeout")))
  |> should.equal(error.Timeout)
}

pub fn ffi_response_message_shape_decodes_test() {
  gluegun_ffi_test_response()
  |> message.decode
  |> should.equal(
    Ok(message.Response(fin.Fin, 200, [#("content-type", "text/plain")])),
  )
}

pub fn ffi_data_message_shape_decodes_binary_body_test() {
  gluegun_ffi_test_data()
  |> message.decode
  |> should.equal(Ok(message.Data(fin.NoFin, <<"hello":utf8>>)))
}

pub fn ffi_stream_refs_are_opaque_test() {
  let stream = gluegun_ffi_test_stream_ref()

  internal.stream(stream)
  |> internal.stream_raw
  |> should.equal(stream)
}

pub fn ffi_ok_nil_result_decodes_to_nil_test() {
  ffi_result.decode_nil_result(Ok(dynamic.nil()))
  |> should.equal(Ok(Nil))
}

pub fn ffi_request_error_result_decodes_instead_of_stream_wrapping_test() {
  ffi_result.decode_request_result(Error(gluegun_ffi_test_erlang_error()))
  |> should.equal(Error(error.ErlangError("Error(Badarg)")))
}

pub fn ffi_non_options_open_errors_are_not_invalid_options_test() {
  message.decode_ffi_error(gluegun_ffi_test_erlang_error())
  |> should.equal(error.ErlangError("Error(Badarg)"))
}

pub fn ffi_close_errors_are_explicit_test() {
  internal.connection(dynamic.string("not-a-pid"))
  |> connection.close
  |> should.equal(Error(error.ConnectionError("Error(SimpleOneForOne)")))
}

pub fn ffi_shutdown_errors_are_explicit_test() {
  internal.connection(dynamic.string("not-a-pid"))
  |> connection.shutdown
  |> should.equal(Error(error.ConnectionError("Error(FunctionClause)")))
}

pub fn ffi_invalid_utf8_websocket_text_is_invalid_message_test() {
  gluegun_ffi_safe_message_to_map(gluegun_ffi_test_invalid_utf8_websocket())
  |> result.map_error(error.decode_ffi_error)
  |> should.equal(Error(error.InvalidMessage("Ws(Text(InvalidUtf8))")))
}

@external(erlang, "gluegun_ffi_test", "test_response_message")
fn gluegun_ffi_test_response() -> dynamic.Dynamic

@external(erlang, "gluegun_ffi_test", "test_data_message")
fn gluegun_ffi_test_data() -> dynamic.Dynamic

@external(erlang, "gluegun_ffi_test", "test_stream_ref")
fn gluegun_ffi_test_stream_ref() -> dynamic.Dynamic

@external(erlang, "gluegun_ffi_test", "test_erlang_error")
fn gluegun_ffi_test_erlang_error() -> dynamic.Dynamic

@external(erlang, "gluegun_ffi_test", "test_invalid_utf8_websocket")
fn gluegun_ffi_test_invalid_utf8_websocket() -> dynamic.Dynamic

@external(erlang, "gluegun_ffi", "safe_message_to_map")
fn gluegun_ffi_safe_message_to_map(
  message: dynamic.Dynamic,
) -> Result(dynamic.Dynamic, dynamic.Dynamic)
