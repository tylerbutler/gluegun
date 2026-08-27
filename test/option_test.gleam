import gleam/option.{None, Some}
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

pub fn option_tests() -> test_tree.TestTree {
  startest.describe("typed options and message decoding", [
    startest.describe("connection options", [
      startest.it("uses default connect options", fn() {
        let options = connection.options()

        options
        |> connection.transport
        |> expect.to_equal(connection.Auto)

        options
        |> connection.protocols
        |> expect.to_equal(None)
      }),
      startest.it("exposes connection option inspectors", fn() {
        connection.options()
        |> connection.transport
        |> expect.to_equal(connection.Auto)
      }),
      startest.it("preserves protocol ordering", fn() {
        connection.options()
        |> connection.with_protocols([connection.Http2, connection.Http1])
        |> connection.protocols
        |> expect.to_equal(Some([connection.Http2, connection.Http1]))
      }),
    ]),
    startest.describe("request options and methods", [
      startest.it("with_headers replaces request headers", fn() {
        request.options()
        |> request.add_headers([#("accept", "application/json")])
        |> request.with_headers([#("x-request-id", "abc")])
        |> request.headers_option
        |> expect.to_equal([#("x-request-id", "abc")])
      }),
      startest.it("add_headers appends request headers", fn() {
        request.options()
        |> request.add_headers([#("accept", "application/json")])
        |> request.add_headers([#("x-request-id", "abc")])
        |> request.headers_option
        |> expect.to_equal([
          #("accept", "application/json"),
          #("x-request-id", "abc"),
        ])
      }),
      startest.it("converts request methods to strings", fn() {
        request.method_to_string(request.Get)
        |> expect.to_equal("GET")

        request.method_to_string(request.Post)
        |> expect.to_equal("POST")

        request.method_to_string(request.Head)
        |> expect.to_equal("HEAD")

        request.method_to_string(request.Put)
        |> expect.to_equal("PUT")

        request.method_to_string(request.Patch)
        |> expect.to_equal("PATCH")

        request.method_to_string(request.Delete)
        |> expect.to_equal("DELETE")

        request.method_to_string(request.Options)
        |> expect.to_equal("OPTIONS")

        request.method_to_string(request.Trace)
        |> expect.to_equal("TRACE")

        request.method_to_string(request.Connect)
        |> expect.to_equal("CONNECT")

        request.method_to_string(request.Custom("PROPFIND"))
        |> expect.to_equal("PROPFIND")
      }),
      startest.it("normalizes request header names", fn() {
        [#("Content-Type", "text/plain"), #("X-Request-ID", "ABC123")]
        |> request.normalize_headers
        |> expect.to_equal([
          #("content-type", "text/plain"),
          #("x-request-id", "ABC123"),
        ])
      }),
    ]),
    startest.describe("responses and messages", [
      startest.it("constructs responses", fn() {
        let constructed_response =
          response.new(
            status: 200,
            headers: [#("content-type", "text/plain")],
            body: <<"hello":utf8>>,
            trailers: [#("expires", "soon")],
          )
          |> response.with_informational(informational: [
            response.Informational(status: 103, headers: [#("server", "gun")]),
          ])

        constructed_response
        |> response.status
        |> expect.to_equal(200)

        constructed_response
        |> response.headers
        |> expect.to_equal([#("content-type", "text/plain")])

        constructed_response
        |> response.body
        |> expect.to_equal(<<"hello":utf8>>)

        constructed_response
        |> response.trailers
        |> expect.to_equal([#("expires", "soon")])

        constructed_response
        |> response.informational
        |> expect.to_equal([
          response.Informational(status: 103, headers: [#("server", "gun")]),
        ])
      }),
      startest.it("constructs messages", fn() {
        message.Response(fin.NoFin, 204, [#("server", "gun")])
        |> expect.to_equal(
          message.Response(fin.NoFin, 204, [#("server", "gun")]),
        )
      }),
      startest.it("decodes response messages", fn() {
        response_message(fin.NoFin, 201, [#("Content-Type", "text/plain")])
        |> safe_decode_message
        |> expect.to_equal(
          Ok(
            message.Response(fin.NoFin, 201, [#("content-type", "text/plain")]),
          ),
        )
      }),
      startest.it("decodes data messages", fn() {
        data_message(fin.Fin, <<"ok":utf8>>)
        |> safe_decode_message
        |> expect.to_equal(Ok(message.Data(fin.Fin, <<"ok":utf8>>)))
      }),
      startest.it("decodes informational messages", fn() {
        inform_message(102, [#("Server", "gun")])
        |> safe_decode_message
        |> expect.to_equal(Ok(message.Inform(102, [#("server", "gun")])))
      }),
      startest.it("matches unsupported feature errors", fn() {
        let unsupported =
          error.UnsupportedFeature("WebSocket upgrade requires HTTP/1.1")
        let error.UnsupportedFeature(reason) = unsupported

        reason |> expect.to_equal("WebSocket upgrade requires HTTP/1.1")
      }),
      startest.it("decodes trailer messages", fn() {
        trailers_message([#("Expires", "soon")])
        |> safe_decode_message
        |> expect.to_equal(Ok(message.Trailers([#("expires", "soon")])))
      }),
      startest.it("decodes upgrade messages", fn() {
        upgrade_message(["websocket"], [#("Connection", "upgrade")])
        |> safe_decode_message
        |> expect.to_equal(
          Ok(message.Upgrade(["websocket"], [#("connection", "upgrade")])),
        )
      }),
      startest.it("decodes push messages", fn() {
        let stream = stream_ref()

        push_message(stream, "POST", "/assets/app.css", [
          #("Accept", "text/css"),
        ])
        |> safe_decode_message
        |> expect.to_equal(
          Ok(
            message.Push(stream, request.Post, "/assets/app.css", [
              #("accept", "text/css"),
            ]),
          ),
        )
      }),
      startest.it("preserves custom push method case", fn() {
        let stream = stream_ref()

        push_message(stream, "PropFind", "/collection", [])
        |> safe_decode_message
        |> expect.to_equal(
          Ok(
            message.Push(stream, request.Custom("PropFind"), "/collection", []),
          ),
        )
      }),
      startest.it("matches known push methods case-insensitively", fn() {
        let stream = stream_ref()

        push_message(stream, "get", "/", [])
        |> safe_decode_message
        |> expect.to_equal(Ok(message.Push(stream, request.Get, "/", [])))
      }),
      startest.it("rejects unknown message tags", fn() {
        unknown_message()
        |> safe_decode_message
        |> expect.to_equal(Error(error.InvalidMessage("Mystery(\"unknown\")")))
      }),
      startest.it("rejects unknown websocket frame tags", fn() {
        unknown_websocket_frame_message()
        |> safe_decode_message
        |> expect.to_equal(
          Error(error.InvalidMessage("Ws(Mystery(\"unknown\"))")),
        )
      }),
      startest.it("decodes websocket messages", fn() {
        websocket_frame_message(text_frame(<<"hello":utf8>>))
        |> safe_decode_message
        |> expect.to_equal(Ok(message.WebSocket(message.Text("hello"))))
      }),
      startest.it(
        "message.decode rejects gun:await/3-style terms with no embedded stream",
        fn() {
          response_message(fin.NoFin, 200, [])
          |> message.decode
          |> expect.to_equal(Error(error.DecodeError("Invalid Gun message")))
        },
      ),
    ]),
  ])
}

/// A raw Gun WebSocket frame term, as carried inside a `{ws, Frame}` message.
type GunFrame

@external(erlang, "gluegun_ffi_test", "stream_ref")
fn stream_ref() -> internal.Stream

@external(erlang, "gluegun_ffi", "safe_decode_message")
fn safe_decode_message(
  message: message.GunMessage,
) -> Result(message.Message, error.GluegunError)

@external(erlang, "gluegun_ffi_test", "inform_message")
fn inform_message(
  status: Int,
  headers: List(#(String, String)),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "response_message")
fn response_message(
  fin: fin.Fin,
  status: Int,
  headers: List(#(String, String)),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "data_message")
fn data_message(fin: fin.Fin, data: BitArray) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "trailers_message")
fn trailers_message(headers: List(#(String, String))) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "push_message")
fn push_message(
  stream: internal.Stream,
  method: String,
  uri: String,
  headers: List(#(String, String)),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "upgrade_message")
fn upgrade_message(
  protocols: List(String),
  headers: List(#(String, String)),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "websocket_frame_message")
fn websocket_frame_message(frame: GunFrame) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "unknown_message")
fn unknown_message() -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "unknown_websocket_frame_message")
fn unknown_websocket_frame_message() -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "text_frame")
fn text_frame(data: BitArray) -> GunFrame
