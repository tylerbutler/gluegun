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
        |> client.with_timeout(timeout(1000))
        |> client.inspect_request
        |> expect.to_equal(client.RequestFields(
          method: request.Get,
          path: "/",
          headers: [#("accept", "application/json")],
          body: <<"":utf8>>,
          options: request.options(),
          timeout: timeout(1000),
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
          timeout: connection.default_timeout(),
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
          timeout: connection.default_timeout(),
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
    startest.describe("failed-stream cleanup", [
      startest.it("cancels on timeout before headers", fn() {
        failure_cleanup([Error(error.Timeout)], error.Timeout, False)
        |> expect.to_equal(Ok(Nil))
      }),
      startest.it("cancels on timeout after partial body", fn() {
        failure_cleanup(
          [
            Ok(message.Response(fin.NoFin, 200, [])),
            Ok(message.Data(fin.NoFin, <<"partial">>)),
            Error(error.Timeout),
          ],
          error.Timeout,
          False,
        )
        |> expect.to_equal(Ok(Nil))
      }),
      startest.it("cancels on invalid collection messages", fn() {
        failure_cleanup(
          [Ok(message.Data(fin.Fin, <<"unexpected">>))],
          error.InvalidMessage("HTTP helper received body before response"),
          False,
        )
        |> expect.to_equal(Ok(Nil))
      }),
      startest.it("cancels on receive and decode failures", fn() {
        failure_cleanup(
          [Error(error.StreamError("reset"))],
          error.StreamError("reset"),
          False,
        )
        |> expect.to_equal(Ok(Nil))
        failure_cleanup(
          [Error(error.DecodeError("malformed"))],
          error.DecodeError("malformed"),
          False,
        )
        |> expect.to_equal(Ok(Nil))
        failure_cleanup(
          [Error(error.ConnectionDown("closed"))],
          error.ConnectionDown("closed"),
          False,
        )
        |> expect.to_equal(Ok(Nil))
      }),
      startest.it("drains even if cancel fails and keeps original error", fn() {
        failure_cleanup([Error(error.Timeout)], error.Timeout, True)
        |> expect.to_equal(Ok(Nil))
      }),
      startest.it("does not cancel successful or rejected requests", fn() {
        no_cleanup(False) |> expect.to_equal(Ok(Nil))
        no_cleanup(True) |> expect.to_equal(Ok(Nil))
      }),
      startest.it("defines the late-message drain race", fn() {
        late_after_drain() |> expect.to_equal(Ok(Nil))
      }),
      startest.it("cancels delayed headers and preserves shared requests", fn() {
        delayed_response(False) |> expect.to_equal(Ok(Nil))
      }),
      startest.it("cancels delayed body and preserves shared requests", fn() {
        delayed_response(True) |> expect.to_equal(Ok(Nil))
      }),
      startest.it("cleans invalid messages on a shared local connection", fn() {
        local_failure(False) |> expect.to_equal(Ok(Nil))
      }),
      startest.it("cleans receive failures on a shared local connection", fn() {
        local_failure(True) |> expect.to_equal(Ok(Nil))
      }),
    ]),
  ])
}

fn timeout(milliseconds: Int) -> connection.Timeout {
  let assert Ok(timeout) = connection.milliseconds(milliseconds)
  timeout
}

fn compile_request_options_helper(should_run: Bool) -> Nil {
  case should_run {
    True -> {
      let _ =
        client.request_options(invalid_connection(), "/", [], timeout(1000))
      Nil
    }
    False -> Nil
  }
}

@external(erlang, "gluegun_ffi_test", "stream_ref")
fn stream_ref() -> internal.Stream

@external(erlang, "gluegun_ffi_test", "invalid_connection")
fn invalid_connection() -> internal.Connection

@external(erlang, "gluegun_client_test", "failure_cleanup")
fn failure_cleanup(
  messages: List(Result(message.Message, error.GluegunError)),
  expected: error.GluegunError,
  invalid_connection: Bool,
) -> Result(Nil, String)

@external(erlang, "gluegun_client_test", "no_cleanup")
fn no_cleanup(send_failure: Bool) -> Result(Nil, String)

@external(erlang, "gluegun_client_test", "late_after_drain")
fn late_after_drain() -> Result(Nil, String)

@external(erlang, "gluegun_client_test", "delayed_response")
fn delayed_response(body_delay: Bool) -> Result(Nil, String)

@external(erlang, "gluegun_client_test", "local_failure")
fn local_failure(receive_failure: Bool) -> Result(Nil, String)
