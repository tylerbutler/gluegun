/// Tests for WebSocket support: frame encoding/decoding, receive routing,
/// await_upgrade routing, and FFI shape validation.
///
/// Tests can be filtered with `gleam test -- --test-name-filter=WebSocket`
/// or by file path with `gleam test -- test/websocket_test.gleam`.
import gleam/erlang/process
import gleam/option.{type Option, None, Some}
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/internal
import gluegun/message
import gluegun/websocket
import gluegun/websocket/raw
import startest
import startest/expect
import startest/test_tree

// ── Frame type variants ──────────────────────────────────────────────────────

pub fn websocket_tests() -> test_tree.TestTree {
  startest.describe("WebSocket support", [
    startest.describe("frame variants", [
      startest.it("supports the close variant", fn() {
        let frame: message.Frame = message.Close
        frame |> expect.to_equal(message.Close)
      }),
      startest.it("supports close-with-reason frames", fn() {
        let frame: message.Frame =
          message.CloseWithReason(1000, <<"normal closure":utf8>>)
        frame
        |> expect.to_equal(
          message.CloseWithReason(1000, <<"normal closure":utf8>>),
        )
      }),
    ]),
    startest.describe("outbound frame encoding", [
      startest.it("encodes text frames", fn() {
        capture_ws_send_frame(message.Text("hello"))
        |> decode_captured_frame
        |> expect.to_equal(Ok(message.WebSocket(message.Text("hello"))))
      }),
      startest.it("encodes binary frames", fn() {
        capture_ws_send_frame(message.Binary(<<0, 1, 2, 255>>))
        |> decode_captured_frame
        |> expect.to_equal(
          Ok(message.WebSocket(message.Binary(<<0, 1, 2, 255>>))),
        )
      }),
      startest.it("encodes ping frames", fn() {
        capture_ws_send_frame(message.Ping(<<"ping":utf8>>))
        |> decode_captured_frame
        |> expect.to_equal(Ok(message.WebSocket(message.Ping(<<"ping":utf8>>))))
      }),
      startest.it("encodes pong frames", fn() {
        capture_ws_send_frame(message.Pong(<<"pong":utf8>>))
        |> decode_captured_frame
        |> expect.to_equal(Ok(message.WebSocket(message.Pong(<<"pong":utf8>>))))
      }),
      startest.it("encodes plain close frames", fn() {
        capture_ws_send_frame(message.Close)
        |> decode_captured_frame
        |> expect.to_equal(Ok(message.WebSocket(message.Close)))
      }),
      startest.it("encodes close-with-reason frames", fn() {
        capture_ws_send_frame(
          message.CloseWithReason(1000, <<"normal closure":utf8>>),
        )
        |> decode_captured_frame
        |> expect.to_equal(
          Ok(
            message.WebSocket(
              message.CloseWithReason(1000, <<"normal closure":utf8>>),
            ),
          ),
        )
      }),
      startest.it("encodes multiple frames", fn() {
        let test_connection = current_connection()
        let test_stream = stream_ref()

        websocket.send_many(test_connection, test_stream, [
          message.Text("hello"),
          message.Binary(<<1, 2, 3>>),
          message.Ping(<<"ping":utf8>>),
        ])
        |> expect.to_equal(Ok(Nil))

        capture_ws_send_frames()
        |> expect.to_equal(
          Ok([
            #("text", <<"hello":utf8>>),
            #("binary", <<1, 2, 3>>),
            #("ping", <<"ping":utf8>>),
          ]),
        )
      }),
      startest.it("surfaces invalid frame list errors", fn() {
        invalid_ws_send_frame_list_result()
        |> expect.to_equal(
          Error(error.InvalidMessage("InvalidFrame(BadFrame)")),
        )
      }),
      startest.it("surfaces invalid UTF-8 text send errors", fn() {
        invalid_ws_send_text_utf8_result()
        |> expect.to_equal(
          Error(error.InvalidMessage("InvalidFrame(Text(InvalidUtf8))")),
        )
      }),
    ]),
    startest.describe("inbound frame decoding", [
      startest.it("decodes text frames", fn() {
        websocket_frame_message(text_frame(<<"hello world":utf8>>))
        |> message.decode
        |> expect.to_equal(Ok(message.WebSocket(message.Text("hello world"))))
      }),
      startest.it("decodes binary frames", fn() {
        websocket_frame_message(binary_frame(<<0, 1, 2, 255>>))
        |> message.decode
        |> expect.to_equal(
          Ok(message.WebSocket(message.Binary(<<0, 1, 2, 255>>))),
        )
      }),
      startest.it("decodes ping frames", fn() {
        websocket_frame_message(ping_frame(<<>>))
        |> message.decode
        |> expect.to_equal(Ok(message.WebSocket(message.Ping(<<>>))))
      }),
      startest.it("decodes pong frames", fn() {
        websocket_frame_message(pong_frame(<<"keepalive":utf8>>))
        |> message.decode
        |> expect.to_equal(
          Ok(message.WebSocket(message.Pong(<<"keepalive":utf8>>))),
        )
      }),
      startest.it("decodes plain close frames", fn() {
        websocket_frame_message(close_frame())
        |> message.decode
        |> expect.to_equal(Ok(message.WebSocket(message.Close)))
      }),
      startest.it("decodes close-with-reason frames", fn() {
        websocket_frame_message(
          close_with_reason_frame(1001, <<"going away":utf8>>),
        )
        |> message.decode
        |> expect.to_equal(
          Ok(
            message.WebSocket(
              message.CloseWithReason(1001, <<"going away":utf8>>),
            ),
          ),
        )
      }),
    ]),
    startest.describe("FFI close frame shapes", [
      startest.it("decodes plain close messages", fn() {
        ws_close_message()
        |> message.decode
        |> expect.to_equal(Ok(message.WebSocket(message.Close)))
      }),
      startest.it("decodes close-with-reason messages", fn() {
        ws_close_with_reason_message()
        |> message.decode
        |> expect.to_equal(
          Ok(
            message.WebSocket(
              message.CloseWithReason(1001, <<"going away":utf8>>),
            ),
          ),
        )
      }),
      startest.it("maps plain close messages safely", fn() {
        ws_close_message()
        |> safe_decode_message
        |> expect.to_equal(Ok(message.WebSocket(message.Close)))
      }),
      startest.it("maps close-with-reason messages safely", fn() {
        ws_close_with_reason_message()
        |> safe_decode_message
        |> expect.to_equal(
          Ok(
            message.WebSocket(
              message.CloseWithReason(1001, <<"going away":utf8>>),
            ),
          ),
        )
      }),
    ]),
    startest.describe("receive routing", [
      startest.it("accepts websocket text messages", fn() {
        websocket.receive_from(Ok(message.WebSocket(message.Text("hi"))))
        |> expect.to_equal(Ok(message.Text("hi")))
      }),
      startest.it("accepts websocket binary messages", fn() {
        websocket.receive_from(
          Ok(message.WebSocket(message.Binary(<<1, 2, 3>>))),
        )
        |> expect.to_equal(Ok(message.Binary(<<1, 2, 3>>)))
      }),
      startest.it("accepts websocket close messages", fn() {
        websocket.receive_from(Ok(message.WebSocket(message.Close)))
        |> expect.to_equal(Ok(message.Close))
      }),
      startest.it("accepts websocket close-with-reason messages", fn() {
        websocket.receive_from(
          Ok(message.WebSocket(message.CloseWithReason(1000, <<"bye":utf8>>))),
        )
        |> expect.to_equal(Ok(message.CloseWithReason(1000, <<"bye":utf8>>)))
      }),
      startest.it("rejects HTTP responses", fn() {
        websocket.receive_from(Ok(message.Response(fin.Fin, 200, [])))
        |> expect.to_equal(
          Error(error.InvalidMessage(
            "websocket.receive: expected WebSocket frame, got HTTP message",
          )),
        )
      }),
      startest.it("rejects HTTP data", fn() {
        websocket.receive_from(Ok(message.Data(fin.Fin, <<"body":utf8>>)))
        |> expect.to_equal(
          Error(error.InvalidMessage(
            "websocket.receive: expected WebSocket frame, got HTTP message",
          )),
        )
      }),
      startest.it("rejects upgrade messages", fn() {
        websocket.receive_from(Ok(message.Upgrade(["websocket"], [])))
        |> expect.to_equal(
          Error(error.InvalidMessage(
            "websocket.receive: expected WebSocket frame, got Upgrade message; call await_upgrade first",
          )),
        )
      }),
      startest.it("propagates timeout errors", fn() {
        websocket.receive_from(Error(error.Timeout))
        |> expect.to_equal(Error(error.Timeout))
      }),
      startest.it("propagates stream errors", fn() {
        websocket.receive_from(Error(error.StreamError("closed")))
        |> expect.to_equal(Error(error.StreamError("closed")))
      }),
    ]),
    startest.describe("WebSocket socket helpers", [
      startest.it(
        "send_text sends Text through the wrapped connection and stream",
        fn() {
          let socket =
            websocket.socket(
              current_connection(),
              stream_ref(),
              connection.Milliseconds(500),
            )

          websocket.send_text(socket, "hello")
          |> expect.to_equal(Ok(Nil))

          capture_ws_send_frames()
          |> expect.to_equal(Ok([#("text", <<"hello":utf8>>)]))
        },
      ),
      startest.it(
        "send_binary sends Binary through the wrapped connection and stream",
        fn() {
          let socket =
            websocket.socket(
              current_connection(),
              stream_ref(),
              connection.Milliseconds(500),
            )

          websocket.send_binary(socket, <<1, 2, 3>>)
          |> expect.to_equal(Ok(Nil))

          capture_ws_send_frames()
          |> expect.to_equal(Ok([#("binary", <<1, 2, 3>>)]))
        },
      ),
      startest.it(
        "ping sends Ping through the wrapped connection and stream",
        fn() {
          let socket =
            websocket.socket(
              current_connection(),
              stream_ref(),
              connection.Milliseconds(500),
            )

          websocket.ping(socket, <<"ping":utf8>>)
          |> expect.to_equal(Ok(Nil))

          capture_ws_send_frames()
          |> expect.to_equal(Ok([#("ping", <<"ping":utf8>>)]))
        },
      ),
      startest.it(
        "pong sends Pong through the wrapped connection and stream",
        fn() {
          let socket =
            websocket.socket(
              current_connection(),
              stream_ref(),
              connection.Milliseconds(500),
            )

          websocket.pong(socket, <<"pong":utf8>>)
          |> expect.to_equal(Ok(Nil))

          capture_ws_send_frames()
          |> expect.to_equal(Ok([#("pong", <<"pong":utf8>>)]))
        },
      ),
      startest.it(
        "send_close_frame sends Close through the wrapped connection and stream",
        fn() {
          let socket =
            websocket.socket(
              current_connection(),
              stream_ref(),
              connection.Milliseconds(500),
            )

          websocket.send_close_frame(socket)
          |> expect.to_equal(Ok(Nil))

          capture_ws_send_frames()
          |> expect.to_equal(Ok([#("close", <<>>)]))
        },
      ),
      startest.it("receive_app_frame returns text frames", fn() {
        websocket.receive_app_frame_from([Ok(message.Text("hello"))], fn(_) {
          Ok(Nil)
        })
        |> expect.to_equal(Ok(message.Text("hello")))
      }),
      startest.it("receive_app_frame returns binary frames", fn() {
        websocket.receive_app_frame_from(
          [Ok(message.Binary(<<1, 2, 3>>))],
          fn(_) { Ok(Nil) },
        )
        |> expect.to_equal(Ok(message.Binary(<<1, 2, 3>>)))
      }),
      startest.it("receive_app_frame returns close frames", fn() {
        websocket.receive_app_frame_from([Ok(message.Close)], fn(_) { Ok(Nil) })
        |> expect.to_equal(Ok(message.Close))
      }),
      startest.it("receive_app_frame returns close-with-reason frames", fn() {
        websocket.receive_app_frame_from(
          [Ok(message.CloseWithReason(1000, <<"bye":utf8>>))],
          fn(_) { Ok(Nil) },
        )
        |> expect.to_equal(Ok(message.CloseWithReason(1000, <<"bye":utf8>>)))
      }),
      startest.it("receive_app_frame skips pong frames", fn() {
        websocket.receive_app_frame_from(
          [
            Ok(message.Pong(<<"ignored":utf8>>)),
            Ok(message.Text("after pong")),
          ],
          fn(_) { Ok(Nil) },
        )
        |> expect.to_equal(Ok(message.Text("after pong")))
      }),
      startest.it(
        "receive_app_frame replies to ping and returns the next app frame",
        fn() {
          websocket.receive_app_frame_from(
            [
              Ok(message.Ping(<<"payload":utf8>>)),
              Ok(message.Text("after ping")),
            ],
            fn(payload) {
              case payload {
                <<"payload":utf8>> -> Ok(Nil)
                _ -> Error(error.InvalidMessage("unexpected pong payload"))
              }
            },
          )
          |> expect.to_equal(Ok(message.Text("after ping")))
        },
      ),
      startest.it(
        "receive_app_frame returns pong send errors immediately",
        fn() {
          websocket.receive_app_frame_from(
            [
              Ok(message.Ping(<<"payload":utf8>>)),
              Ok(message.Text("unreached")),
            ],
            fn(_) { Error(error.StreamError("send failed")) },
          )
          |> expect.to_equal(Error(error.StreamError("send failed")))
        },
      ),
    ]),
    startest.describe("WebSocket session options", [
      startest.it(
        "defaults to HTTP/1, no headers, default upgrade options, and 5000ms timeout",
        fn() {
          let options = websocket.options()

          options
          |> websocket.options_connect_options
          |> connection.protocols
          |> expect.to_equal(Some([connection.Http1]))

          options
          |> websocket.options_headers
          |> expect.to_equal([])

          options
          |> websocket.options_upgrade_options
          |> websocket.upgrade_options_to_ffi
          |> expect.to_equal([])

          options
          |> websocket.options_timeout
          |> expect.to_equal(connection.Milliseconds(5000))
        },
      ),
      startest.it("with_headers updates only headers", fn() {
        let original = websocket.options()
        let updated =
          original
          |> websocket.with_headers([#("sec-websocket-protocol", "chat")])

        updated
        |> websocket.options_headers
        |> expect.to_equal([#("sec-websocket-protocol", "chat")])

        updated
        |> websocket.options_connect_options
        |> connection.protocols
        |> expect.to_equal(
          original
          |> websocket.options_connect_options
          |> connection.protocols,
        )

        updated
        |> websocket.options_timeout
        |> expect.to_equal(websocket.options_timeout(original))

        updated
        |> websocket.options_upgrade_options
        |> websocket.upgrade_options_to_ffi
        |> expect.to_equal(
          original
          |> websocket.options_upgrade_options
          |> websocket.upgrade_options_to_ffi,
        )
      }),
      startest.it("with_connect_options updates only connection options", fn() {
        let original = websocket.options()
        let connect_options =
          connection.options()
          |> connection.with_transport(transport: connection.Tcp)
        let updated =
          original
          |> websocket.with_connect_options(connect_options)

        updated
        |> websocket.options_connect_options
        |> connection.transport
        |> expect.to_equal(connection.Tcp)

        updated
        |> websocket.options_headers
        |> expect.to_equal(websocket.options_headers(original))

        updated
        |> websocket.options_timeout
        |> expect.to_equal(websocket.options_timeout(original))

        updated
        |> websocket.options_upgrade_options
        |> websocket.upgrade_options_to_ffi
        |> expect.to_equal(
          original
          |> websocket.options_upgrade_options
          |> websocket.upgrade_options_to_ffi,
        )
      }),
      startest.it("with_upgrade_options updates only upgrade options", fn() {
        let original = websocket.options()
        let upgrade_options =
          websocket.upgrade_options()
          |> websocket.with_compress(True)
        let updated =
          original
          |> websocket.with_upgrade_options(upgrade_options)

        updated
        |> websocket.options_upgrade_options
        |> websocket.upgrade_options_to_ffi
        |> expect.to_equal([websocket.Compress(True)])

        updated
        |> websocket.options_headers
        |> expect.to_equal(websocket.options_headers(original))

        updated
        |> websocket.options_connect_options
        |> connection.protocols
        |> expect.to_equal(
          original
          |> websocket.options_connect_options
          |> connection.protocols,
        )

        updated
        |> websocket.options_timeout
        |> expect.to_equal(websocket.options_timeout(original))
      }),
      startest.it("with_timeout updates only timeout", fn() {
        let original = websocket.options()
        let updated =
          original
          |> websocket.with_timeout(connection.Infinity)

        updated
        |> websocket.options_timeout
        |> expect.to_equal(connection.Infinity)

        updated
        |> websocket.options_headers
        |> expect.to_equal(websocket.options_headers(original))

        updated
        |> websocket.options_connect_options
        |> connection.protocols
        |> expect.to_equal(
          original
          |> websocket.options_connect_options
          |> connection.protocols,
        )

        updated
        |> websocket.options_upgrade_options
        |> websocket.upgrade_options_to_ffi
        |> expect.to_equal(
          original
          |> websocket.options_upgrade_options
          |> websocket.upgrade_options_to_ffi,
        )
      }),
    ]),
    startest.describe("WebSocket session cleanup", [
      startest.it(
        "returns callback value when callback and cleanup succeed",
        fn() {
          websocket.with_socket_result(Ok("done"), Ok(Nil), Ok(Nil))
          |> expect.to_equal(Ok("done"))
        },
      ),
      startest.it(
        "returns close-frame cleanup errors after callback success",
        fn() {
          websocket.with_socket_result(
            Ok("done"),
            Error(error.StreamError("close frame failed")),
            Ok(Nil),
          )
          |> expect.to_equal(Error(error.StreamError("close frame failed")))
        },
      ),
      startest.it(
        "returns connection cleanup errors after callback success",
        fn() {
          websocket.with_socket_result(
            Ok("done"),
            Ok(Nil),
            Error(error.ConnectionError("connection close failed")),
          )
          |> expect.to_equal(
            Error(error.ConnectionError("connection close failed")),
          )
        },
      ),
      startest.it(
        "returns the callback error after callback failure even when cleanup fails",
        fn() {
          websocket.with_socket_result(
            Error(error.InvalidMessage("callback failed")),
            Error(error.StreamError("close frame failed")),
            Error(error.ConnectionError("connection close failed")),
          )
          |> expect.to_equal(Error(error.InvalidMessage("callback failed")))
        },
      ),
    ]),
    startest.describe("upgrade routing", [
      startest.it("accepts upgrade messages", fn() {
        websocket.await_upgrade_from(Ok(message.Upgrade(["websocket"], [])))
        |> expect.to_equal(Ok(Nil))
      }),
      startest.it("accepts upgrade messages with headers", fn() {
        websocket.await_upgrade_from(
          Ok(
            message.Upgrade(["websocket"], [#("sec-websocket-protocol", "chat")]),
          ),
        )
        |> expect.to_equal(Ok(Nil))
      }),
      startest.it("rejects websocket frames while awaiting upgrade", fn() {
        websocket.await_upgrade_from(
          Ok(message.WebSocket(message.Text("oops"))),
        )
        |> expect.to_equal(
          Error(error.InvalidMessage(
            "websocket.await_upgrade: expected Upgrade message",
          )),
        )
      }),
      startest.it("rejects HTTP responses while awaiting upgrade", fn() {
        websocket.await_upgrade_from(Ok(message.Response(fin.Fin, 101, [])))
        |> expect.to_equal(
          Error(error.InvalidMessage(
            "websocket.await_upgrade: expected Upgrade message",
          )),
        )
      }),
      startest.it("propagates timeout while awaiting upgrade", fn() {
        websocket.await_upgrade_from(Error(error.Timeout))
        |> expect.to_equal(Error(error.Timeout))
      }),
      startest.it("rejects HTTP/2 before calling FFI", fn() {
        websocket.upgrade_with_protocol(
          invalid_connection(),
          connection.Http2,
          "/ws",
          [],
        )
        |> expect.to_equal(
          Error(error.UnsupportedFeature("WebSocket upgrade requires HTTP/1.1")),
        )
      }),
      startest.it("surfaces FFI errors from upgrade", fn() {
        // Gun does not support WebSocket over HTTP/2 (RFC 8441). That
        // limitation is documented in src/gluegun/websocket.gleam and the echo
        // example. This deterministic test does not create an HTTP/2 connection; it
        // verifies that errors raised by gun:ws_upgrade are surfaced as Result errors
        // rather than panicking or producing a misleading success.
        websocket.upgrade(invalid_connection(), "/ws", [])
        |> expect.to_equal(Error(error.ErlangError("Error(FunctionClause)")))
      }),
    ]),
    startest.describe("upgrade injection guards", [
      startest.it("rejects a CRLF-split upgrade path", fn() {
        websocket.upgrade(
          current_connection(),
          "/ws HTTP/1.1\r\nX-Injected: evil",
          [],
        )
        |> expect.to_equal(Error(error.InvalidOptions("Request(InvalidPath)")))
      }),
      startest.it("rejects a CRLF-injected upgrade header value", fn() {
        websocket.upgrade(current_connection(), "/ws", [
          #("X-Trace", "abc\r\nX-Injected: evil"),
        ])
        |> expect.to_equal(
          Error(error.InvalidOptions("Request(InvalidHeaderValue)")),
        )
      }),
      startest.it("rejects an invalid upgrade header name", fn() {
        websocket.upgrade(current_connection(), "/ws", [
          #("X-Trace: evil", "abc"),
        ])
        |> expect.to_equal(
          Error(error.InvalidOptions("Request(InvalidHeaderName)")),
        )
      }),
      startest.it(
        "rejects a caller-supplied Transfer-Encoding upgrade header",
        fn() {
          websocket.upgrade(current_connection(), "/ws", [
            #("Transfer-Encoding", "chunked"),
          ])
          |> expect.to_equal(
            Error(error.InvalidOptions(
              "Request(ForbiddenTransferEncodingHeader)",
            )),
          )
        },
      ),
    ]),
    startest.describe("WebSocket upgrade options", [
      startest.it("encodes default options to an empty option list", fn() {
        websocket.upgrade_options()
        |> websocket.upgrade_options_to_ffi
        |> expect.to_equal([])
      }),
      startest.it("encodes typed Gun ws_opts fields", fn() {
        websocket.upgrade_options()
        |> websocket.with_compress(True)
        |> websocket.with_silence_pings(True)
        |> websocket.with_flow(8)
        |> websocket.with_keepalive(connection.Milliseconds(30_000))
        |> websocket.with_closing_timeout(connection.Infinity)
        |> websocket.upgrade_options_to_ffi
        |> expect.to_equal([
          websocket.SilencePings(True),
          websocket.Keepalive(connection.Milliseconds(30_000)),
          websocket.Flow(8),
          websocket.Compress(True),
          websocket.ClosingTimeout(connection.Infinity),
        ])
      }),
      startest.it("preserves protocol module values", fn() {
        websocket.upgrade_options()
        |> websocket.with_default_protocol_module("my_ws_h")
        |> websocket.with_protocol_module("chat", "chat_ws_h")
        |> websocket.upgrade_options_to_ffi
        |> expect.to_equal([
          websocket.Protocols([#("chat", "chat_ws_h")]),
          websocket.DefaultProtocol("my_ws_h"),
        ])
      }),
      startest.it("preserves reply_to, tunnel, and handler options", fn() {
        let reply_to = process.self()
        let tunnel = stream_ref()
        let handler_options = raw.handler_options(#(1, "two"))

        websocket.upgrade_options()
        |> raw.with_reply_to(reply_to)
        |> raw.with_tunnel(tunnel)
        |> raw.with_handler_options(handler_options)
        |> websocket.upgrade_options_to_ffi
        |> expect.to_equal([
          websocket.UserOptions(handler_options),
          websocket.Tunnel(tunnel),
          websocket.ReplyTo(reply_to),
        ])
      }),
      startest.it("normalizes typed options before calling Gun", fn() {
        websocket.upgrade_options()
        |> websocket.with_compress(True)
        |> websocket.with_silence_pings(False)
        |> websocket.with_flow(16)
        |> websocket.with_keepalive(connection.Milliseconds(45_000))
        |> websocket.with_closing_timeout(connection.Infinity)
        |> websocket.upgrade_options_to_ffi
        |> capture_ws_upgrade_options
        |> expect.to_equal(
          Ok(
            captured_ws_options(
              compress: Some(True),
              silence_pings: Some(False),
              flow: Some(16),
              keepalive: Some("45000"),
              closing_timeout: Some("infinity"),
              default_protocol: None,
              protocols: [],
            ),
          ),
        )
      }),
      startest.it("normalizes protocol modules before calling Gun", fn() {
        websocket.upgrade_options()
        |> websocket.with_default_protocol_module("gluegun_ws_test")
        |> websocket.with_protocol_module("chat", "gluegun_ws_test")
        |> websocket.upgrade_options_to_ffi
        |> capture_ws_upgrade_options
        |> expect.to_equal(
          Ok(
            captured_ws_options(
              compress: None,
              silence_pings: None,
              flow: None,
              keepalive: None,
              closing_timeout: None,
              default_protocol: Some("gluegun_ws_test"),
              protocols: [#("chat", "gluegun_ws_test")],
            ),
          ),
        )
      }),
      startest.it(
        "rejects unknown default protocol modules before calling Gun",
        fn() {
          websocket.upgrade_options()
          |> websocket.with_default_protocol_module(
            "gluegun_nonexistent_ws_handler",
          )
          |> websocket.upgrade_options_to_ffi
          |> capture_ws_upgrade_options
          |> expect.to_equal(
            Error(error.InvalidOptions(
              "Ws(UnknownModule(\"gluegun_nonexistent_ws_handler\"))",
            )),
          )
        },
      ),
      startest.it("rejects unknown protocol modules before calling Gun", fn() {
        websocket.upgrade_options()
        |> websocket.with_protocol_module(
          "chat",
          "gluegun_nonexistent_protocol_ws_handler",
        )
        |> websocket.upgrade_options_to_ffi
        |> capture_ws_upgrade_options
        |> expect.to_equal(
          Error(error.InvalidOptions(
            "Ws(UnknownModule(\"gluegun_nonexistent_protocol_ws_handler\"))",
          )),
        )
      }),
      startest.it("returns InvalidOptions for invalid Gun ws_opts", fn() {
        invalid_ws_upgrade_options_result()
        |> expect.to_equal(Error(error.InvalidOptions("Ws(Compress)")))
      }),
    ]),
  ])
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Gun `ws_opts()` projected back into Gleam by `gluegun_ws_test`:
/// `#(compress, silence_pings, flow, keepalive, closing_timeout,
/// default_protocol, protocols)`. Timeouts are rendered as strings so
/// `infinity` and a millisecond count share one type.
type CapturedWebSocketOptions =
  #(
    Option(Bool),
    Option(Bool),
    Option(Int),
    Option(String),
    Option(String),
    Option(String),
    List(#(String, String)),
  )

/// A raw Gun WebSocket frame term, as carried inside a `{ws, Frame}` message.
type GunFrame

fn captured_ws_options(
  compress compress: Option(Bool),
  silence_pings silence_pings: Option(Bool),
  flow flow: Option(Int),
  keepalive keepalive: Option(String),
  closing_timeout closing_timeout: Option(String),
  default_protocol default_protocol: Option(String),
  protocols protocols: List(#(String, String)),
) -> CapturedWebSocketOptions {
  #(
    compress,
    silence_pings,
    flow,
    keepalive,
    closing_timeout,
    default_protocol,
    protocols,
  )
}

/// Decode a frame Gun was asked to send back into a typed message, so outbound
/// encoding can be asserted against the same `Frame` values callers pass in.
fn decode_captured_frame(
  captured: Result(message.GunMessage, error.GluegunError),
) -> Result(message.Message, error.GluegunError) {
  case captured {
    Ok(gun_message) -> message.decode(gun_message)
    Error(error) -> Error(error)
  }
}

@external(erlang, "gluegun_ffi_test", "current_connection")
fn current_connection() -> internal.Connection

@external(erlang, "gluegun_ffi_test", "invalid_connection")
fn invalid_connection() -> internal.Connection

@external(erlang, "gluegun_ffi_test", "stream_ref")
fn stream_ref() -> internal.Stream

@external(erlang, "gluegun_ffi_test", "websocket_frame_message")
fn websocket_frame_message(frame: GunFrame) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "text_frame")
fn text_frame(data: BitArray) -> GunFrame

@external(erlang, "gluegun_ffi_test", "binary_frame")
fn binary_frame(data: BitArray) -> GunFrame

@external(erlang, "gluegun_ffi_test", "ping_frame")
fn ping_frame(data: BitArray) -> GunFrame

@external(erlang, "gluegun_ffi_test", "pong_frame")
fn pong_frame(data: BitArray) -> GunFrame

@external(erlang, "gluegun_ffi_test", "close_frame")
fn close_frame() -> GunFrame

@external(erlang, "gluegun_ffi_test", "close_with_reason_frame")
fn close_with_reason_frame(code: Int, reason: BitArray) -> GunFrame

@external(erlang, "gluegun_ffi", "safe_decode_message")
fn safe_decode_message(
  message: message.GunMessage,
) -> Result(message.Message, error.GluegunError)

@external(erlang, "gluegun_ws_test", "ws_close_message")
fn ws_close_message() -> message.GunMessage

@external(erlang, "gluegun_ws_test", "ws_close_with_reason_message")
fn ws_close_with_reason_message() -> message.GunMessage

@external(erlang, "gluegun_ws_test", "capture_ws_send_frame")
fn capture_ws_send_frame(
  frame: message.Frame,
) -> Result(message.GunMessage, error.GluegunError)

@external(erlang, "gluegun_ws_test", "capture_ws_send_frames")
fn capture_ws_send_frames() -> Result(List(#(String, BitArray)), Nil)

@external(erlang, "gluegun_ws_test", "capture_ws_upgrade_options")
fn capture_ws_upgrade_options(
  options: List(websocket.UpgradeOption),
) -> Result(CapturedWebSocketOptions, error.GluegunError)

@external(erlang, "gluegun_ws_test", "invalid_ws_send_frame_list_result")
fn invalid_ws_send_frame_list_result() -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ws_test", "invalid_ws_send_text_utf8_result")
fn invalid_ws_send_text_utf8_result() -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ws_test", "invalid_ws_upgrade_options_result")
fn invalid_ws_upgrade_options_result() -> Result(
  internal.Stream,
  error.GluegunError,
)
