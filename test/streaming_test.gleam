import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/atom
import gluegun/error
import gluegun/fin
import gluegun/internal
import gluegun/internal/ffi_result
import gluegun/request
import startest.{describe, it}
import startest/expect

pub fn streaming_tests() {
  describe("streaming requests", [
    describe("request FFI shapes", [
      it("exposes start_stream helper name", fn() {
        compile_start_stream_helper(False)
        |> expect.to_equal(Nil)
      }),
      it("normalizes streaming request headers", fn() {
        let #(method, path, headers, _options) =
          request.headers_args_to_ffi(
            request.Post,
            "/upload",
            [#("Content-Type", "text/plain")],
            request.options()
              |> request.add_headers([#("X-Trace", "abc")]),
          )

        method
        |> expect.to_equal("POST")

        path
        |> expect.to_equal("/upload")

        headers
        |> expect.to_equal([
          #("content-type", "text/plain"),
          #("x-trace", "abc"),
        ])
      }),
      it("decodes opaque stream request results", fn() {
        let raw_stream = dynamic.string("stream-ref")

        ffi_result.decode_request_result(Ok(raw_stream))
        |> expect.to_equal(Ok(internal.stream(raw_stream)))
      }),
      it("encodes fin values for streaming data", fn() {
        request.fin_to_ffi(fin.Fin)
        |> decode.run(atom.decoder())
        |> expect.to_equal(Ok(atom.create("fin")))

        request.fin_to_ffi(fin.NoFin)
        |> decode.run(atom.decoder())
        |> expect.to_equal(Ok(atom.create("nofin")))
      }),
      it("accepts typed fin values for streaming data", fn() {
        let _send = send_streaming_data

        request.fin_to_ffi(fin.Fin)
        |> decode.run(atom.decoder())
        |> expect.to_equal(Ok(atom.create("fin")))

        request.fin_to_ffi(fin.NoFin)
        |> decode.run(atom.decoder())
        |> expect.to_equal(Ok(atom.create("nofin")))
      }),
    ]),
    describe("stream control", [
      it("decodes cancel success and error results", fn() {
        ffi_result.decode_nil_result(Ok(dynamic.nil()))
        |> expect.to_equal(Ok(Nil))

        ffi_result.decode_nil_result(Error(gluegun_ffi_test_stream_error()))
        |> expect.to_equal(Error(error.StreamError("Boom")))
      }),
      it("encodes update_flow increments", fn() {
        let connection = internal.connection(dynamic.string("conn"))
        let stream = internal.stream(dynamic.string("stream"))
        let #(raw_connection, raw_stream, increment) =
          request.update_flow_args_to_ffi(connection, stream, 1234)

        raw_connection
        |> expect.to_equal(dynamic.string("conn"))

        raw_stream
        |> expect.to_equal(dynamic.string("stream"))

        increment
        |> expect.to_equal(1234)
      }),
      it("decodes update_flow success and error results", fn() {
        ffi_result.decode_nil_result(Ok(dynamic.nil()))
        |> expect.to_equal(Ok(Nil))

        ffi_result.decode_nil_result(Error(gluegun_ffi_test_stream_error()))
        |> expect.to_equal(Error(error.StreamError("Boom")))
      }),
      it("rejects zero update_flow increments", fn() {
        request.update_flow(
          internal.connection(dynamic.string("conn")),
          internal.stream(dynamic.string("stream")),
          0,
        )
        |> expect.to_equal(
          Error(error.InvalidOptions("flow-control increment must be positive")),
        )
      }),
      it("rejects negative update_flow increments", fn() {
        request.update_flow(
          internal.connection(dynamic.string("conn")),
          internal.stream(dynamic.string("stream")),
          -1,
        )
        |> expect.to_equal(
          Error(error.InvalidOptions("flow-control increment must be positive")),
        )
      }),
    ]),
  ])
}

fn compile_start_stream_helper(should_run: Bool) -> Nil {
  case should_run {
    True -> {
      let _ =
        request.start_stream(
          internal.connection(dynamic.string("conn")),
          request.Post,
          "/upload",
          [],
          request.options(),
        )
      Nil
    }
    False -> Nil
  }
}

fn send_streaming_data(
  connection: internal.Connection,
  stream: internal.Stream,
  fin: fin.Fin,
  data: BitArray,
) {
  request.data(connection, stream, fin, data)
}

@external(erlang, "gluegun_ffi_test", "test_stream_error")
fn gluegun_ffi_test_stream_error() -> dynamic.Dynamic
