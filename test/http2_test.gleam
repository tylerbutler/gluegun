import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/process
import gleam/list
import gleam/result
import gleeunit/should
import gluegun/client
import gluegun/connection
import gluegun/error
import gluegun/internal
import gluegun/message
import gluegun/response
import gluegun/types

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

pub fn http2_await_up_then_get_response_path_succeeds_test() {
  let negotiated =
    connection.decode_await_up_result(Ok(atom.to_dynamic(atom.create("http2"))))
  negotiated
  |> should.equal(Ok(connection.Http2))

  let request_subject = process.new_subject()
  let message_subject = process.new_subject()
  let test_connection = internal.connection(dynamic.string("connection"))
  let test_stream = internal.stream(dynamic.string("stream"))
  let expected_path = "/deterministic-http2"
  let expected_headers = [#("accept", "text/plain"), #("x-test", "http2")]

  process.send(
    message_subject,
    Ok(message.Response(message.NoFin, 200, [#("content-type", "text/plain")])),
  )
  process.send(
    message_subject,
    Ok(message.Data(message.Fin, <<"hello from deterministic get":utf8>>)),
  )

  let fake_request = fn(_connection, method, path, headers, body, _options) {
    process.send(request_subject, #(method, path, headers, body))
    Ok(test_stream)
  }
  let fake_await = fn(_connection, stream, _timeout) {
    stream
    |> should.equal(test_stream)

    case process.receive(message_subject, within: 0) {
      Ok(next) -> next
      Error(_) -> Error(error.Timeout)
    }
  }

  let actual = case negotiated {
    Ok(connection.Http2) ->
      client.get_with(
        test_connection,
        expected_path,
        expected_headers,
        connection.Milliseconds(10),
        fake_request,
        fake_await,
      )
    _ -> Error(error.DecodeError("HTTP/2 was not negotiated"))
  }

  actual
  |> should.equal(
    Ok(
      response.new(
        status: 200,
        headers: [#("content-type", "text/plain")],
        body: <<"hello from deterministic get":utf8>>,
        trailers: [],
      ),
    ),
  )
  process.receive(request_subject, within: 0)
  |> should.equal(Ok(#(types.Get, expected_path, expected_headers, <<>>)))
}
