import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/list
import gleam/result
import gleeunit/should
import gluegun/client
import gluegun/connection
import gluegun/error
import gluegun/message
import gluegun/response

pub fn http2_protocol_preference_encodes_to_ffi_in_order_test() {
  connection.connect_options()
  |> connection.with_protocols([connection.Http2, connection.Http1])
  |> connection.options_to_ffi
  |> decode.run(decode.at(["protocols"], decode.list(atom.decoder())))
  |> result.map(list.map(_, atom.to_string))
  |> should.equal(Ok(["http2", "http"]))
}

pub fn http2_await_up_result_decodes_protocol_test() {
  connection.decode_await_up_result(Ok(atom.to_dynamic(atom.create("http2"))))
  |> should.equal(Ok(connection.Http2))
}

pub fn http2_invalid_await_up_protocol_returns_decode_error_test() {
  connection.decode_await_up_result(Ok(atom.to_dynamic(atom.create("spdy"))))
  |> should.equal(Error(error.DecodeError("Invalid protocol")))
}

pub fn http2_like_response_stream_collects_normal_http_response_test() {
  client.collect_messages([
    Ok(message.Response(message.NoFin, 200, [#("content-type", "text/plain")])),
    Ok(message.Data(message.NoFin, <<"hello ":utf8>>)),
    Ok(message.Data(message.NoFin, <<"from ":utf8>>)),
    Ok(message.Data(message.Fin, <<"http2":utf8>>)),
  ])
  |> should.equal(
    Ok(
      response.new(
        status: 200,
        headers: [#("content-type", "text/plain")],
        body: <<"hello from http2":utf8>>,
        trailers: [],
      ),
    ),
  )
}
