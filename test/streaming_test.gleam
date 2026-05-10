import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/atom
import gleeunit/should
import gluegun/error
import gluegun/fin
import gluegun/internal
import gluegun/internal/ffi_result
import gluegun/request

pub fn streaming_headers_ffi_shape_normalizes_request_test() {
  let #(method, path, headers, _options) =
    request.headers_args_to_ffi(
      request.Post,
      "/upload",
      [#("Content-Type", "text/plain")],
      request.request_options()
        |> request.with_headers([#("X-Trace", "abc")]),
    )

  method
  |> should.equal("POST")

  path
  |> should.equal("/upload")

  headers
  |> should.equal([#("content-type", "text/plain"), #("x-trace", "abc")])
}

pub fn streaming_headers_result_decodes_opaque_stream_test() {
  let raw_stream = dynamic.string("stream-ref")

  ffi_result.decode_request_result(Ok(raw_stream))
  |> should.equal(Ok(internal.stream(raw_stream)))
}

pub fn streaming_data_fin_encodes_expected_ffi_values_test() {
  request.fin_to_ffi(fin.Fin)
  |> decode.run(atom.decoder())
  |> should.equal(Ok(atom.create("fin")))

  request.fin_to_ffi(fin.NoFin)
  |> decode.run(atom.decoder())
  |> should.equal(Ok(atom.create("nofin")))
}

pub fn streaming_data_accepts_typed_fin_values_test() {
  let _send = send_streaming_data

  request.fin_to_ffi(fin.Fin)
  |> decode.run(atom.decoder())
  |> should.equal(Ok(atom.create("fin")))

  request.fin_to_ffi(fin.NoFin)
  |> decode.run(atom.decoder())
  |> should.equal(Ok(atom.create("nofin")))
}

fn send_streaming_data(
  connection: internal.Connection,
  stream: internal.Stream,
  fin: fin.Fin,
  data: BitArray,
) {
  request.data(connection, stream, fin, data)
}

pub fn streaming_cancel_decodes_success_and_error_test() {
  ffi_result.decode_nil_result(Ok(dynamic.nil()))
  |> should.equal(Ok(Nil))

  ffi_result.decode_nil_result(Error(gluegun_ffi_test_stream_error()))
  |> should.equal(Error(error.StreamError("Boom")))
}

pub fn streaming_update_flow_ffi_shape_encodes_increment_test() {
  let connection = internal.connection(dynamic.string("conn"))
  let stream = internal.stream(dynamic.string("stream"))
  let #(raw_connection, raw_stream, increment) =
    request.update_flow_args_to_ffi(connection, stream, 1234)

  raw_connection
  |> should.equal(dynamic.string("conn"))

  raw_stream
  |> should.equal(dynamic.string("stream"))

  increment
  |> should.equal(1234)
}

pub fn streaming_update_flow_decodes_success_and_error_test() {
  ffi_result.decode_nil_result(Ok(dynamic.nil()))
  |> should.equal(Ok(Nil))

  ffi_result.decode_nil_result(Error(gluegun_ffi_test_stream_error()))
  |> should.equal(Error(error.StreamError("Boom")))
}

pub fn streaming_update_flow_rejects_zero_increment_test() {
  request.update_flow(
    internal.connection(dynamic.string("conn")),
    internal.stream(dynamic.string("stream")),
    0,
  )
  |> should.equal(
    Error(error.InvalidOptions("flow-control increment must be positive")),
  )
}

pub fn streaming_update_flow_rejects_negative_increment_test() {
  request.update_flow(
    internal.connection(dynamic.string("conn")),
    internal.stream(dynamic.string("stream")),
    -1,
  )
  |> should.equal(
    Error(error.InvalidOptions("flow-control increment must be positive")),
  )
}

@external(erlang, "gluegun_ffi_test", "test_stream_error")
fn gluegun_ffi_test_stream_error() -> dynamic.Dynamic
