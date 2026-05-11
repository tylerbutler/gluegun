import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/list
import gleam/result
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/internal
import gluegun/internal/ffi_result
import gluegun/message
import startest.{describe, it}
import startest/expect

pub fn ffi_shape_tests() {
  describe("FFI shape decoding", [
    describe("typed option conversion", [
      it("converts timeouts", fn() {
        decode.run(
          connection.timeout_to_ffi(connection.Milliseconds(123)),
          decode.int,
        )
        |> expect.to_equal(Ok(123))

        decode.run(
          connection.timeout_to_ffi(connection.Infinity),
          atom.decoder(),
        )
        |> expect.to_equal(Ok(atom.create("infinity")))
      }),
      it("preserves protocol ordering", fn() {
        connection.options()
        |> connection.with_protocols([connection.Http2, connection.Http1])
        |> connection.options_to_ffi
        |> decode.run(decode.at(["protocols"], decode.list(atom.decoder())))
        |> result.map(list.map(_, atom.to_string))
        |> expect.to_equal(Ok(["http2", "http"]))
      }),
    ]),
    describe("message and error shapes", [
      it("preserves invalid await_up protocol decode errors", fn() {
        connection.decode_await_up_result(
          Ok(atom.to_dynamic(atom.create("spdy"))),
        )
        |> expect.to_equal(Error(error.DecodeError("Invalid protocol")))
      }),
      it("maps timeout errors", fn() {
        message.decode_ffi_error(atom.to_dynamic(atom.create("timeout")))
        |> expect.to_equal(error.Timeout)
      }),
      it("decodes response message shapes", fn() {
        gluegun_ffi_test_response()
        |> message.decode
        |> expect.to_equal(
          Ok(message.Response(fin.Fin, 200, [#("content-type", "text/plain")])),
        )
      }),
      it("decodes binary body data message shapes", fn() {
        gluegun_ffi_test_data()
        |> message.decode
        |> expect.to_equal(Ok(message.Data(fin.NoFin, <<"hello":utf8>>)))
      }),
      it("keeps stream refs opaque", fn() {
        let stream = gluegun_ffi_test_stream_ref()

        internal.stream(stream)
        |> internal.stream_raw
        |> expect.to_equal(stream)
      }),
      it("decodes ok nil results", fn() {
        ffi_result.decode_nil_result(Ok(dynamic.nil()))
        |> expect.to_equal(Ok(Nil))
      }),
      it("decodes request errors instead of wrapping them as streams", fn() {
        ffi_result.decode_request_result(Error(gluegun_ffi_test_erlang_error()))
        |> expect.to_equal(Error(error.ErlangError("Error(Badarg)")))
      }),
      it("keeps non-option open errors explicit", fn() {
        message.decode_ffi_error(gluegun_ffi_test_erlang_error())
        |> expect.to_equal(error.ErlangError("Error(Badarg)"))
      }),
      it("keeps close errors explicit", fn() {
        internal.connection(dynamic.string("not-a-pid"))
        |> connection.close
        |> expect.to_equal(
          Error(error.ConnectionError("Error(SimpleOneForOne)")),
        )
      }),
      it("keeps shutdown errors explicit", fn() {
        internal.connection(dynamic.string("not-a-pid"))
        |> connection.shutdown
        |> expect.to_equal(
          Error(error.ConnectionError("Error(FunctionClause)")),
        )
      }),
      it("rejects invalid UTF-8 websocket text", fn() {
        gluegun_ffi_safe_message_to_map(
          gluegun_ffi_test_invalid_utf8_websocket(),
        )
        |> result.map_error(error.decode_ffi_error)
        |> expect.to_equal(Error(error.InvalidMessage("Ws(Text(InvalidUtf8))")))
      }),
    ]),
  ])
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
