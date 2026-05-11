import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/process
import gleam/list
import gleam/result
import gluegun/client
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/internal
import gluegun/message
import gluegun/request
import gluegun/response
import startest.{describe, it}
import startest/expect

pub fn http2_tests() {
  describe("HTTP/2 support", [
    describe("protocol negotiation", [
      it("encodes protocol preference in order", fn() {
        connection.options()
        |> connection.with_protocols([connection.Http2, connection.Http1])
        |> connection.options_to_ffi
        |> decode.run(decode.at(["protocols"], decode.list(atom.decoder())))
        |> result.map(list.map(_, atom.to_string))
        |> expect.to_equal(Ok(["http2", "http"]))
      }),
      it("decodes await_up protocol results", fn() {
        connection.decode_await_up_result(
          Ok(atom.to_dynamic(atom.create("http2"))),
        )
        |> expect.to_equal(Ok(connection.Http2))
      }),
      it("returns decode errors for invalid await_up protocols", fn() {
        connection.decode_await_up_result(
          Ok(atom.to_dynamic(atom.create("spdy"))),
        )
        |> expect.to_equal(Error(error.DecodeError("Invalid protocol")))
      }),
    ]),
    describe("HTTP helper compatibility", [
      it("collects normal HTTP responses from HTTP/2-like streams", fn() {
        client.collect_messages([
          Ok(
            message.Response(fin.NoFin, 200, [#("content-type", "text/plain")]),
          ),
          Ok(message.Data(fin.NoFin, <<"hello ":utf8>>)),
          Ok(message.Data(fin.NoFin, <<"from ":utf8>>)),
          Ok(message.Data(fin.Fin, <<"http2":utf8>>)),
        ])
        |> expect.to_equal(
          Ok(
            response.new(
              status: 200,
              headers: [#("content-type", "text/plain")],
              body: <<"hello from http2":utf8>>,
              trailers: [],
            ),
          ),
        )
      }),
      it("uses the negotiated HTTP/2 response path", fn() {
        let negotiated =
          connection.decode_await_up_result(
            Ok(atom.to_dynamic(atom.create("http2"))),
          )
        negotiated
        |> expect.to_equal(Ok(connection.Http2))

        let request_subject = process.new_subject()
        let message_subject = process.new_subject()
        let test_connection = internal.connection(dynamic.string("connection"))
        let test_stream = internal.stream(dynamic.string("stream"))
        let expected_path = "/deterministic-http2"
        let expected_headers = [#("accept", "text/plain"), #("x-test", "http2")]

        process.send(
          message_subject,
          Ok(
            message.Response(fin.NoFin, 200, [#("content-type", "text/plain")]),
          ),
        )
        process.send(
          message_subject,
          Ok(message.Data(fin.Fin, <<"hello from deterministic get":utf8>>)),
        )

        let fake_request = fn(
          _connection,
          method,
          path,
          headers,
          body,
          _options,
        ) {
          process.send(request_subject, #(method, path, headers, body))
          Ok(test_stream)
        }
        let fake_await = fn(_connection, stream, _timeout) {
          stream
          |> expect.to_equal(test_stream)

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
        |> expect.to_equal(
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
        |> expect.to_equal(
          Ok(#(request.Get, expected_path, expected_headers, <<>>)),
        )
      }),
    ]),
  ])
}
