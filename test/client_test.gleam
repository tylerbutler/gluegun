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

pub fn client_tests() -> test_tree.TestTree {
  startest.describe("HTTP client helpers", [
    startest.describe("request builder", [
      startest.it("sets request fields", fn() {
        client.new(request.Get, "/")
        |> client.with_header("accept", "application/json")
        |> client.with_body(<<"":utf8>>)
        |> client.with_timeout(connection.Milliseconds(1000))
        |> client.inspect_request
        |> expect.to_equal(client.RequestFields(
          method: request.Get,
          path: "/",
          headers: [#("accept", "application/json")],
          body: <<"":utf8>>,
          options: request.options(),
          timeout: connection.Milliseconds(1000),
        ))
      }),
      startest.it("exposes request_options helper name", fn() {
        compile_request_options_helper(False)
        |> expect.to_equal(Nil)
      }),
      startest.it("add_headers appends request headers", fn() {
        client.new(request.Get, "/")
        |> client.add_headers([#("accept", "application/json")])
        |> client.add_headers([#("x-request-id", "abc")])
        |> client.inspect_request
        |> expect.to_equal(client.RequestFields(
          method: request.Get,
          path: "/",
          headers: [
            #("accept", "application/json"),
            #("x-request-id", "abc"),
          ],
          body: <<>>,
          options: request.options(),
          timeout: connection.Milliseconds(5000),
        ))
      }),
      startest.it("with_headers replaces request headers", fn() {
        client.new(request.Get, "/")
        |> client.add_headers([#("accept", "application/json")])
        |> client.with_headers([#("x-request-id", "abc")])
        |> client.inspect_request
        |> expect.to_equal(client.RequestFields(
          method: request.Get,
          path: "/",
          headers: [#("x-request-id", "abc")],
          body: <<>>,
          options: request.options(),
          timeout: connection.Milliseconds(5000),
        ))
      }),
    ]),
    startest.describe("response collection", [
      startest.it("collects a single final body", fn() {
        client.collect_messages([
          Ok(
            message.Response(fin.NoFin, 200, [#("content-type", "text/plain")]),
          ),
          Ok(message.Data(fin.Fin, <<"hello":utf8>>)),
        ])
        |> expect.to_equal(
          Ok(
            response.new(
              status: 200,
              headers: [#("content-type", "text/plain")],
              body: <<"hello":utf8>>,
              trailers: [],
            ),
          ),
        )
      }),
      startest.it("collects multiple data chunks in order", fn() {
        let assert Ok(collected_response) =
          client.collect_messages([
            Ok(message.Response(fin.NoFin, 200, [])),
            Ok(message.Data(fin.NoFin, <<"chunk-1|":utf8>>)),
            Ok(message.Data(fin.NoFin, <<"chunk-2|":utf8>>)),
            Ok(message.Data(fin.NoFin, <<"chunk-3|":utf8>>)),
            Ok(message.Data(fin.NoFin, <<"chunk-4|":utf8>>)),
            Ok(message.Data(fin.Fin, <<"chunk-5":utf8>>)),
          ])

        collected_response
        |> response.body
        |> expect.to_equal(<<"chunk-1|chunk-2|chunk-3|chunk-4|chunk-5":utf8>>)
      }),
      startest.it("preserves trailers", fn() {
        let assert Ok(collected_response) =
          client.collect_messages([
            Ok(message.Response(fin.NoFin, 200, [])),
            Ok(message.Data(fin.NoFin, <<"hello":utf8>>)),
            Ok(message.Trailers([#("expires", "soon")])),
          ])

        collected_response
        |> response.trailers
        |> expect.to_equal([#("expires", "soon")])
      }),
      startest.it("preserves informational responses", fn() {
        let assert Ok(collected_response) =
          client.collect_messages([
            Ok(message.Inform(103, [#("link", "</style.css>; rel=preload")])),
            Ok(message.Response(fin.Fin, 204, [#("server", "gun")])),
          ])

        collected_response
        |> response.informational
        |> expect.to_equal([
          response.Informational(status: 103, headers: [
            #("link", "</style.css>; rel=preload"),
          ]),
        ])
      }),
    ]),
    startest.describe("invalid message handling", [
      startest.it(
        "rejects informational responses after the final response",
        fn() {
          client.collect_messages([
            Ok(message.Response(fin.NoFin, 200, [])),
            Ok(message.Inform(103, [])),
          ])
          |> expect.to_equal(
            Error(error.InvalidMessage(
              "HTTP helper received informational response after final response",
            )),
          )
        },
      ),
      startest.it("rejects push, upgrade, and websocket messages", fn() {
        let stream = stream_ref()

        client.collect_messages([
          Ok(message.Push(stream, request.Get, "/pushed", [])),
        ])
        |> expect.to_equal(
          Error(error.InvalidMessage("HTTP helper received push message")),
        )

        client.collect_messages([Ok(message.Upgrade(["websocket"], []))])
        |> expect.to_equal(
          Error(error.InvalidMessage("HTTP helper received upgrade message")),
        )

        client.collect_messages([Ok(message.WebSocket(message.Text("hello")))])
        |> expect.to_equal(
          Error(error.InvalidMessage("HTTP helper received websocket message")),
        )
      }),
      startest.it("rejects body data before a response", fn() {
        client.collect_messages([Ok(message.Data(fin.Fin, <<"oops":utf8>>))])
        |> expect.to_equal(
          Error(error.InvalidMessage(
            "HTTP helper received body before response",
          )),
        )
      }),
      startest.it("rejects duplicate final responses", fn() {
        client.collect_messages([
          Ok(message.Response(fin.NoFin, 200, [])),
          Ok(message.Response(fin.Fin, 204, [])),
        ])
        |> expect.to_equal(
          Error(error.InvalidMessage("HTTP helper received duplicate response")),
        )
      }),
      startest.it("rejects trailers before a response", fn() {
        client.collect_messages([Ok(message.Trailers([#("expires", "soon")]))])
        |> expect.to_equal(
          Error(error.InvalidMessage(
            "HTTP helper received trailers before response",
          )),
        )
      }),
      startest.it("propagates timeout and connection-down errors", fn() {
        client.collect_messages([Error(error.Timeout)])
        |> expect.to_equal(Error(error.Timeout))

        client.collect_messages([Error(error.ConnectionDown("closed"))])
        |> expect.to_equal(Error(error.ConnectionDown("closed")))
      }),
    ]),
    startest.describe("response body text", [
      startest.it("decodes UTF-8 bodies", fn() {
        response.new(
          status: 200,
          headers: [],
          body: <<"héllo":utf8>>,
          trailers: [],
        )
        |> response.body_text
        |> expect.to_equal(Ok("héllo"))
      }),
      startest.it("rejects invalid UTF-8 bodies", fn() {
        response.new(status: 200, headers: [], body: <<255>>, trailers: [])
        |> response.body_text
        |> expect.to_equal(
          Error(error.DecodeError("Response body is not valid UTF-8")),
        )
      }),
    ]),
  ])
}

fn compile_request_options_helper(should_run: Bool) -> Nil {
  case should_run {
    True -> {
      let _ =
        client.request_options(
          invalid_connection(),
          "/",
          [],
          connection.Milliseconds(1000),
        )
      Nil
    }
    False -> Nil
  }
}

@external(erlang, "gluegun_ffi_test", "stream_ref")
fn stream_ref() -> internal.Stream

@external(erlang, "gluegun_ffi_test", "invalid_connection")
fn invalid_connection() -> internal.Connection
