import gleam/dynamic
import gleam/option.{None, Some}
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/internal
import gluegun/message
import gluegun/request
import gluegun/response
import startest.{describe, it}
import startest/expect

pub fn options_tests() {
  describe("typed options and message decoding", [
    describe("connection options", [
      it("uses default connect options", fn() {
        let options = connection.options()

        options
        |> connection.transport
        |> expect.to_equal(connection.Auto)

        options
        |> connection.protocols
        |> expect.to_equal(None)
      }),
      it("exposes connection option inspectors", fn() {
        connection.options()
        |> connection.transport
        |> expect.to_equal(connection.Auto)
      }),
      it("preserves protocol ordering", fn() {
        connection.options()
        |> connection.with_protocols([connection.Http2, connection.Http1])
        |> connection.protocols
        |> expect.to_equal(Some([connection.Http2, connection.Http1]))
      }),
    ]),
    describe("request options and methods", [
      it("with_headers replaces request headers", fn() {
        request.options()
        |> request.add_headers([#("accept", "application/json")])
        |> request.with_headers([#("x-request-id", "abc")])
        |> request.headers_option
        |> expect.to_equal([#("x-request-id", "abc")])
      }),
      it("add_headers appends request headers", fn() {
        request.options()
        |> request.add_headers([#("accept", "application/json")])
        |> request.add_headers([#("x-request-id", "abc")])
        |> request.headers_option
        |> expect.to_equal([
          #("accept", "application/json"),
          #("x-request-id", "abc"),
        ])
      }),
      it("converts request methods to strings", fn() {
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
      it("normalizes request header names", fn() {
        [#("Content-Type", "text/plain"), #("X-Request-ID", "ABC123")]
        |> request.normalize_headers
        |> expect.to_equal([
          #("content-type", "text/plain"),
          #("x-request-id", "ABC123"),
        ])
      }),
    ]),
    describe("responses and messages", [
      it("constructs responses", fn() {
        let res =
          response.new(
            status: 200,
            headers: [#("content-type", "text/plain")],
            body: <<"hello":utf8>>,
            trailers: [#("expires", "soon")],
          )
          |> response.with_informational(informational: [
            response.Informational(status: 103, headers: [#("server", "gun")]),
          ])

        res
        |> response.status
        |> expect.to_equal(200)

        res
        |> response.headers
        |> expect.to_equal([#("content-type", "text/plain")])

        res
        |> response.body
        |> expect.to_equal(<<"hello":utf8>>)

        res
        |> response.trailers
        |> expect.to_equal([#("expires", "soon")])

        res
        |> response.informational
        |> expect.to_equal([
          response.Informational(status: 103, headers: [#("server", "gun")]),
        ])
      }),
      it("constructs messages", fn() {
        message.Response(fin.NoFin, 204, [#("server", "gun")])
        |> expect.to_equal(
          message.Response(fin.NoFin, 204, [#("server", "gun")]),
        )
      }),
      it("decodes response messages", fn() {
        let value =
          dynamic.properties([
            #(dynamic.string("type"), dynamic.string("response")),
            #(dynamic.string("fin"), dynamic.bool(False)),
            #(dynamic.string("status"), dynamic.int(201)),
            #(
              dynamic.string("headers"),
              dynamic.list([
                dynamic.array([
                  dynamic.string("Content-Type"),
                  dynamic.string("text/plain"),
                ]),
              ]),
            ),
          ])

        message.decode(value)
        |> expect.to_equal(
          Ok(
            message.Response(fin.NoFin, 201, [#("content-type", "text/plain")]),
          ),
        )
      }),
      it("decodes data messages", fn() {
        let value =
          dynamic.properties([
            #(dynamic.string("type"), dynamic.string("data")),
            #(dynamic.string("fin"), dynamic.bool(True)),
            #(dynamic.string("data"), dynamic.bit_array(<<"ok":utf8>>)),
          ])

        message.decode(value)
        |> expect.to_equal(Ok(message.Data(fin.Fin, <<"ok":utf8>>)))
      }),
      it("decodes informational messages", fn() {
        let value =
          dynamic.properties([
            #(dynamic.string("type"), dynamic.string("inform")),
            #(dynamic.string("status"), dynamic.int(102)),
            #(
              dynamic.string("headers"),
              dynamic.list([
                dynamic.array([dynamic.string("Server"), dynamic.string("gun")]),
              ]),
            ),
          ])

        message.decode(value)
        |> expect.to_equal(Ok(message.Inform(102, [#("server", "gun")])))
      }),
      it("matches unsupported feature errors", fn() {
        let unsupported =
          error.UnsupportedFeature("WebSocket upgrade requires HTTP/1.1")
        let error.UnsupportedFeature(reason) = unsupported

        reason |> expect.to_equal("WebSocket upgrade requires HTTP/1.1")
      }),
      it("decodes trailer messages", fn() {
        let value =
          dynamic.properties([
            #(dynamic.string("type"), dynamic.string("trailers")),
            #(
              dynamic.string("headers"),
              dynamic.list([
                dynamic.array([
                  dynamic.string("Expires"),
                  dynamic.string("soon"),
                ]),
              ]),
            ),
          ])

        message.decode(value)
        |> expect.to_equal(Ok(message.Trailers([#("expires", "soon")])))
      }),
      it("decodes upgrade messages", fn() {
        let value =
          dynamic.properties([
            #(dynamic.string("type"), dynamic.string("upgrade")),
            #(
              dynamic.string("protocols"),
              dynamic.list([dynamic.string("websocket")]),
            ),
            #(
              dynamic.string("headers"),
              dynamic.list([
                dynamic.array([
                  dynamic.string("Connection"),
                  dynamic.string("upgrade"),
                ]),
              ]),
            ),
          ])

        message.decode(value)
        |> expect.to_equal(
          Ok(message.Upgrade(["websocket"], [#("connection", "upgrade")])),
        )
      }),
      it("decodes push messages", fn() {
        let stream = dynamic.string("stream-1")
        let value =
          dynamic.properties([
            #(dynamic.string("type"), dynamic.string("push")),
            #(dynamic.string("stream"), stream),
            #(dynamic.string("method"), dynamic.string("POST")),
            #(dynamic.string("uri"), dynamic.string("/assets/app.css")),
            #(
              dynamic.string("headers"),
              dynamic.list([
                dynamic.array([
                  dynamic.string("Accept"),
                  dynamic.string("text/css"),
                ]),
              ]),
            ),
          ])

        message.decode(value)
        |> expect.to_equal(
          Ok(
            message.Push(
              internal.stream(stream),
              request.Post,
              "/assets/app.css",
              [
                #("accept", "text/css"),
              ],
            ),
          ),
        )
      }),
      it("preserves custom push method case", fn() {
        let stream = dynamic.string("stream-1")
        let value =
          dynamic.properties([
            #(dynamic.string("type"), dynamic.string("push")),
            #(dynamic.string("stream"), stream),
            #(dynamic.string("method"), dynamic.string("PropFind")),
            #(dynamic.string("uri"), dynamic.string("/collection")),
            #(dynamic.string("headers"), dynamic.list([])),
          ])

        message.decode(value)
        |> expect.to_equal(
          Ok(
            message.Push(
              internal.stream(stream),
              request.Custom("PropFind"),
              "/collection",
              [],
            ),
          ),
        )
      }),
      it("matches known push methods case-insensitively", fn() {
        let stream = dynamic.string("stream-1")
        let value =
          dynamic.properties([
            #(dynamic.string("type"), dynamic.string("push")),
            #(dynamic.string("stream"), stream),
            #(dynamic.string("method"), dynamic.string("get")),
            #(dynamic.string("uri"), dynamic.string("/")),
            #(dynamic.string("headers"), dynamic.list([])),
          ])

        message.decode(value)
        |> expect.to_equal(
          Ok(message.Push(internal.stream(stream), request.Get, "/", [])),
        )
      }),
      it("rejects unknown message tags", fn() {
        let value =
          dynamic.properties([
            #(dynamic.string("type"), dynamic.string("mystery")),
          ])

        message.decode(value)
        |> expect.to_equal(Error(error.DecodeError("Invalid Gun message")))
      }),
      it("rejects unknown websocket frame tags", fn() {
        let value =
          dynamic.properties([
            #(dynamic.string("type"), dynamic.string("websocket")),
            #(
              dynamic.string("frame"),
              dynamic.properties([
                #(dynamic.string("type"), dynamic.string("mystery")),
              ]),
            ),
          ])

        message.decode(value)
        |> expect.to_equal(Error(error.DecodeError("Invalid Gun message")))
      }),
      it("decodes websocket messages", fn() {
        let value =
          dynamic.properties([
            #(dynamic.string("type"), dynamic.string("websocket")),
            #(
              dynamic.string("frame"),
              dynamic.properties([
                #(dynamic.string("type"), dynamic.string("text")),
                #(dynamic.string("data"), dynamic.string("hello")),
              ]),
            ),
          ])

        message.decode(value)
        |> expect.to_equal(Ok(message.WebSocket(message.Text("hello"))))
      }),
    ]),
  ])
}
