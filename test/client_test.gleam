import gleam/dynamic
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

pub fn client_tests() {
  describe("HTTP client helpers", [
    describe("request builder", [
      it("sets request fields", fn() {
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
      it("exposes request_options helper name", fn() {
        compile_request_options_helper(False)
        |> expect.to_equal(Nil)
      }),
      it("add_headers appends request headers", fn() {
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
      it("with_headers replaces request headers", fn() {
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
    describe("response collection", [
      it("collects a single final body", fn() {
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
      it("collects multiple data chunks in order", fn() {
        let assert Ok(res) =
          client.collect_messages([
            Ok(message.Response(fin.NoFin, 200, [])),
            Ok(message.Data(fin.NoFin, <<"chunk-1|":utf8>>)),
            Ok(message.Data(fin.NoFin, <<"chunk-2|":utf8>>)),
            Ok(message.Data(fin.NoFin, <<"chunk-3|":utf8>>)),
            Ok(message.Data(fin.NoFin, <<"chunk-4|":utf8>>)),
            Ok(message.Data(fin.Fin, <<"chunk-5":utf8>>)),
          ])

        res
        |> response.body
        |> expect.to_equal(<<"chunk-1|chunk-2|chunk-3|chunk-4|chunk-5":utf8>>)
      }),
      it("preserves trailers", fn() {
        let assert Ok(res) =
          client.collect_messages([
            Ok(message.Response(fin.NoFin, 200, [])),
            Ok(message.Data(fin.NoFin, <<"hello":utf8>>)),
            Ok(message.Trailers([#("expires", "soon")])),
          ])

        res
        |> response.trailers
        |> expect.to_equal([#("expires", "soon")])
      }),
      it("preserves informational responses", fn() {
        let assert Ok(res) =
          client.collect_messages([
            Ok(message.Inform(103, [#("link", "</style.css>; rel=preload")])),
            Ok(message.Response(fin.Fin, 204, [#("server", "gun")])),
          ])

        res
        |> response.informational
        |> expect.to_equal([
          response.Informational(status: 103, headers: [
            #("link", "</style.css>; rel=preload"),
          ]),
        ])
      }),
    ]),
    describe("invalid message handling", [
      it("rejects informational responses after the final response", fn() {
        client.collect_messages([
          Ok(message.Response(fin.NoFin, 200, [])),
          Ok(message.Inform(103, [])),
        ])
        |> expect.to_equal(
          Error(error.InvalidMessage(
            "HTTP helper received informational response after final response",
          )),
        )
      }),
      it("rejects push, upgrade, and websocket messages", fn() {
        let stream = internal.stream(dynamic.string("stream-1"))

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
      it("rejects body data before a response", fn() {
        client.collect_messages([Ok(message.Data(fin.Fin, <<"oops":utf8>>))])
        |> expect.to_equal(
          Error(error.InvalidMessage(
            "HTTP helper received body before response",
          )),
        )
      }),
      it("rejects duplicate final responses", fn() {
        client.collect_messages([
          Ok(message.Response(fin.NoFin, 200, [])),
          Ok(message.Response(fin.Fin, 204, [])),
        ])
        |> expect.to_equal(
          Error(error.InvalidMessage("HTTP helper received duplicate response")),
        )
      }),
      it("rejects trailers before a response", fn() {
        client.collect_messages([Ok(message.Trailers([#("expires", "soon")]))])
        |> expect.to_equal(
          Error(error.InvalidMessage(
            "HTTP helper received trailers before response",
          )),
        )
      }),
      it("propagates timeout and connection-down errors", fn() {
        client.collect_messages([Error(error.Timeout)])
        |> expect.to_equal(Error(error.Timeout))

        client.collect_messages([Error(error.ConnectionDown("closed"))])
        |> expect.to_equal(Error(error.ConnectionDown("closed")))
      }),
    ]),
    describe("response body text", [
      it("decodes UTF-8 bodies", fn() {
        response.new(
          status: 200,
          headers: [],
          body: <<"héllo":utf8>>,
          trailers: [],
        )
        |> response.body_text
        |> expect.to_equal(Ok("héllo"))
      }),
      it("rejects invalid UTF-8 bodies", fn() {
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
          internal.connection(dynamic.string("conn")),
          "/",
          [],
          connection.Milliseconds(1000),
        )
      Nil
    }
    False -> Nil
  }
}
