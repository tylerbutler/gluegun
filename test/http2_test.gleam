import gleam/erlang/process
import gluegun/client
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/internal
import gluegun/message
import gluegun/request
import gluegun/response
import startest
import startest/expect
import startest/test_tree

pub fn http2_tests() -> test_tree.TestTree {
  startest.describe("HTTP/2 support", [
    startest.describe("protocol negotiation", [
      startest.it("encodes protocol preference in order", fn() {
        connection.options()
        |> connection.with_protocols([connection.Http2, connection.Http1])
        |> connection.options_to_ffi
        |> expect.to_equal([
          connection.TransportOption(connection.Auto),
          connection.RetryOption(connection.Milliseconds(5000)),
          connection.ConnectTimeoutOption(connection.Milliseconds(5000)),
          connection.ProtocolsOption([connection.Http2, connection.Http1]),
        ])
      }),
      startest.it("decodes await_up protocol results", fn() {
        gun_protocol_result("http2")
        |> expect.to_equal(Ok(connection.Http2))
      }),
      startest.it("returns decode errors for invalid await_up protocols", fn() {
        gun_protocol_result("spdy")
        |> expect.to_equal(Error(error.DecodeError("Invalid protocol")))
      }),
    ]),
    startest.describe("HTTP helper compatibility", [
      startest.it(
        "collects normal HTTP responses from HTTP/2-like streams",
        fn() {
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
        },
      ),
      startest.it("uses the negotiated HTTP/2 response path", fn() {
        let negotiated = gun_protocol_result("http2")
        negotiated
        |> expect.to_equal(Ok(connection.Http2))

        let request_subject = process.new_subject()
        let message_subject = process.new_subject()
        let test_connection = invalid_connection()
        let test_stream = stream_ref()
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
          _connection: connection.Connection,
          method: request.Method,
          path: String,
          headers: List(request.Header),
          body: BitArray,
          _options: request.RequestOptions,
        ) -> Result(request.Stream, error.GluegunError) {
          process.send(request_subject, #(method, path, headers, body))
          Ok(test_stream)
        }
        let fake_await = fn(
          _connection: connection.Connection,
          stream: request.Stream,
          _timeout: connection.Timeout,
        ) -> Result(message.Message, error.GluegunError) {
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
          Ok(connection.Http1) ->
            Error(error.DecodeError("HTTP/2 was not negotiated"))
          Error(_) -> Error(error.DecodeError("HTTP/2 was not negotiated"))
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

@external(erlang, "gluegun_ffi_test", "protocol_result")
fn gun_protocol_result(
  protocol: String,
) -> Result(connection.Protocol, error.GluegunError)

@external(erlang, "gluegun_ffi_test", "invalid_connection")
fn invalid_connection() -> internal.Connection

@external(erlang, "gluegun_ffi_test", "stream_ref")
fn stream_ref() -> internal.Stream
