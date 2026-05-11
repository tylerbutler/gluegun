/// Tests for WebSocket support: frame encoding/decoding, receive routing,
/// await_upgrade routing, and FFI shape validation.
///
/// Tests can be filtered with `gleam test -- --test-name-filter=WebSocket`
/// or by file path with `gleam test -- test/websocket_test.gleam`.
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/list
import gleam/option.{Some}
import gleam/result
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/internal
import gluegun/message
import gluegun/websocket
import startest.{describe, it}
import startest/expect

// ── Frame type variants ──────────────────────────────────────────────────────

pub fn websocket_tests() {
  describe("WebSocket support", [
    describe("frame variants", [
      it("supports the close variant", fn() {
        let frame: message.Frame = message.Close
        frame |> expect.to_equal(message.Close)
      }),
      it("supports close-with-reason frames", fn() {
        let frame: message.Frame =
          message.CloseWithReason(1000, <<"normal closure":utf8>>)
        frame
        |> expect.to_equal(
          message.CloseWithReason(1000, <<"normal closure":utf8>>),
        )
      }),
    ]),
    describe("outbound frame encoding", [
      it("encodes text frames", fn() {
        capture_ws_send_frame_message(message.Text("hello"))
        |> result.map_error(error.decode_ffi_error)
        |> result.try(message.decode)
        |> expect.to_equal(Ok(message.WebSocket(message.Text("hello"))))
      }),
      it("encodes binary frames", fn() {
        capture_ws_send_frame_message(message.Binary(<<0, 1, 2, 255>>))
        |> result.map_error(error.decode_ffi_error)
        |> result.try(message.decode)
        |> expect.to_equal(
          Ok(message.WebSocket(message.Binary(<<0, 1, 2, 255>>))),
        )
      }),
      it("encodes ping frames", fn() {
        capture_ws_send_frame_message(message.Ping(<<"ping":utf8>>))
        |> result.map_error(error.decode_ffi_error)
        |> result.try(message.decode)
        |> expect.to_equal(Ok(message.WebSocket(message.Ping(<<"ping":utf8>>))))
      }),
      it("encodes pong frames", fn() {
        capture_ws_send_frame_message(message.Pong(<<"pong":utf8>>))
        |> result.map_error(error.decode_ffi_error)
        |> result.try(message.decode)
        |> expect.to_equal(Ok(message.WebSocket(message.Pong(<<"pong":utf8>>))))
      }),
      it("encodes plain close frames", fn() {
        capture_ws_send_frame_message(message.Close)
        |> result.map_error(error.decode_ffi_error)
        |> result.try(message.decode)
        |> expect.to_equal(Ok(message.WebSocket(message.Close)))
      }),
      it("encodes close-with-reason frames", fn() {
        capture_ws_send_frame_message(
          message.CloseWithReason(1000, <<"normal closure":utf8>>),
        )
        |> result.map_error(error.decode_ffi_error)
        |> result.try(message.decode)
        |> expect.to_equal(
          Ok(
            message.WebSocket(
              message.CloseWithReason(1000, <<"normal closure":utf8>>),
            ),
          ),
        )
      }),
      it("encodes multiple frames", fn() {
        let fake_conn = internal.connection(gluegun_ws_test_current_process())
        let fake_stream = internal.stream(dynamic.string("test-stream"))

        websocket.send_many(fake_conn, fake_stream, [
          message.Text("hello"),
          message.Binary(<<1, 2, 3>>),
          message.Ping(<<"ping":utf8>>),
        ])
        |> expect.to_equal(Ok(Nil))

        capture_ws_send_message()
        |> expect.to_equal(
          Ok([
            #("text", <<"hello":utf8>>),
            #("binary", <<1, 2, 3>>),
            #("ping", <<"ping":utf8>>),
          ]),
        )
      }),
      it("surfaces invalid frame errors", fn() {
        gluegun_ws_test_invalid_ws_send_frame_result()
        |> result.map_error(error.decode_ffi_error)
        |> expect.to_equal(
          Error(error.InvalidMessage("InvalidFrame(BadFrame)")),
        )
      }),
      it("surfaces invalid frame list errors", fn() {
        gluegun_ws_test_invalid_ws_send_frame_list_result()
        |> result.map_error(error.decode_ffi_error)
        |> expect.to_equal(
          Error(error.InvalidMessage("InvalidFrame(BadFrame)")),
        )
      }),
      it("surfaces invalid UTF-8 text send errors", fn() {
        gluegun_ws_test_invalid_ws_send_text_utf8_result()
        |> result.map_error(error.decode_ffi_error)
        |> expect.to_equal(
          Error(error.InvalidMessage("InvalidFrame(Text(InvalidUtf8))")),
        )
      }),
    ]),
    describe("inbound frame decoding", [
      it("decodes text frames", fn() {
        make_ws_frame_map("text", [#("data", dynamic.string("hello world"))])
        |> message.decode
        |> expect.to_equal(Ok(message.WebSocket(message.Text("hello world"))))
      }),
      it("decodes binary frames", fn() {
        make_ws_frame_map("binary", [
          #("data", dynamic.bit_array(<<0, 1, 2, 255>>)),
        ])
        |> message.decode
        |> expect.to_equal(
          Ok(message.WebSocket(message.Binary(<<0, 1, 2, 255>>))),
        )
      }),
      it("decodes ping frames", fn() {
        make_ws_frame_map("ping", [#("data", dynamic.bit_array(<<>>))])
        |> message.decode
        |> expect.to_equal(Ok(message.WebSocket(message.Ping(<<>>))))
      }),
      it("decodes pong frames", fn() {
        make_ws_frame_map("pong", [
          #("data", dynamic.bit_array(<<"keepalive":utf8>>)),
        ])
        |> message.decode
        |> expect.to_equal(
          Ok(message.WebSocket(message.Pong(<<"keepalive":utf8>>))),
        )
      }),
      it("decodes plain close frames", fn() {
        make_ws_frame_map("close", [])
        |> message.decode
        |> expect.to_equal(Ok(message.WebSocket(message.Close)))
      }),
      it("decodes close-with-reason frames", fn() {
        make_ws_frame_map("close_with_reason", [
          #("code", dynamic.int(1001)),
          #("reason", dynamic.bit_array(<<"going away":utf8>>)),
        ])
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
    describe("FFI close frame shapes", [
      it("decodes plain close messages", fn() {
        gluegun_ws_test_close_plain_message()
        |> message.decode
        |> expect.to_equal(Ok(message.WebSocket(message.Close)))
      }),
      it("decodes close-with-reason messages", fn() {
        gluegun_ws_test_close_with_reason_message()
        |> message.decode
        |> expect.to_equal(
          Ok(
            message.WebSocket(
              message.CloseWithReason(1001, <<"going away":utf8>>),
            ),
          ),
        )
      }),
      it("maps plain close messages safely", fn() {
        gluegun_ws_test_ws_close_gun_tuple()
        |> gluegun_ffi_safe_message_to_map
        |> result.map_error(error.decode_ffi_error)
        |> result.try(message.decode)
        |> expect.to_equal(Ok(message.WebSocket(message.Close)))
      }),
      it("maps close-with-reason messages safely", fn() {
        gluegun_ws_test_ws_close_with_reason_gun_tuple()
        |> gluegun_ffi_safe_message_to_map
        |> result.map_error(error.decode_ffi_error)
        |> result.try(message.decode)
        |> expect.to_equal(
          Ok(
            message.WebSocket(
              message.CloseWithReason(1001, <<"going away":utf8>>),
            ),
          ),
        )
      }),
    ]),
    describe("receive routing", [
      it("accepts websocket text messages", fn() {
        websocket.receive_from(Ok(message.WebSocket(message.Text("hi"))))
        |> expect.to_equal(Ok(message.Text("hi")))
      }),
      it("accepts websocket binary messages", fn() {
        websocket.receive_from(
          Ok(message.WebSocket(message.Binary(<<1, 2, 3>>))),
        )
        |> expect.to_equal(Ok(message.Binary(<<1, 2, 3>>)))
      }),
      it("accepts websocket close messages", fn() {
        websocket.receive_from(Ok(message.WebSocket(message.Close)))
        |> expect.to_equal(Ok(message.Close))
      }),
      it("accepts websocket close-with-reason messages", fn() {
        websocket.receive_from(
          Ok(message.WebSocket(message.CloseWithReason(1000, <<"bye":utf8>>))),
        )
        |> expect.to_equal(Ok(message.CloseWithReason(1000, <<"bye":utf8>>)))
      }),
      it("rejects HTTP responses", fn() {
        websocket.receive_from(Ok(message.Response(fin.Fin, 200, [])))
        |> expect.to_equal(
          Error(error.InvalidMessage(
            "websocket.receive: expected WebSocket frame, got HTTP message",
          )),
        )
      }),
      it("rejects HTTP data", fn() {
        websocket.receive_from(Ok(message.Data(fin.Fin, <<"body":utf8>>)))
        |> expect.to_equal(
          Error(error.InvalidMessage(
            "websocket.receive: expected WebSocket frame, got HTTP message",
          )),
        )
      }),
      it("rejects upgrade messages", fn() {
        websocket.receive_from(Ok(message.Upgrade(["websocket"], [])))
        |> expect.to_equal(
          Error(error.InvalidMessage(
            "websocket.receive: expected WebSocket frame, got Upgrade message; call await_upgrade first",
          )),
        )
      }),
      it("propagates timeout errors", fn() {
        websocket.receive_from(Error(error.Timeout))
        |> expect.to_equal(Error(error.Timeout))
      }),
      it("propagates stream errors", fn() {
        websocket.receive_from(Error(error.StreamError("closed")))
        |> expect.to_equal(Error(error.StreamError("closed")))
      }),
    ]),
    describe("WebSocket socket helpers", [
      it("send_text sends Text through the wrapped connection and stream", fn() {
        let socket =
          websocket.socket(
            internal.connection(gluegun_ws_test_current_process()),
            internal.stream(dynamic.string("socket-stream")),
            connection.Milliseconds(500),
          )

        websocket.send_text(socket, "hello")
        |> expect.to_equal(Ok(Nil))

        capture_ws_send_message()
        |> expect.to_equal(Ok([#("text", <<"hello":utf8>>)]))
      }),
      it(
        "send_binary sends Binary through the wrapped connection and stream",
        fn() {
          let socket =
            websocket.socket(
              internal.connection(gluegun_ws_test_current_process()),
              internal.stream(dynamic.string("socket-stream")),
              connection.Milliseconds(500),
            )

          websocket.send_binary(socket, <<1, 2, 3>>)
          |> expect.to_equal(Ok(Nil))

          capture_ws_send_message()
          |> expect.to_equal(Ok([#("binary", <<1, 2, 3>>)]))
        },
      ),
      it("ping sends Ping through the wrapped connection and stream", fn() {
        let socket =
          websocket.socket(
            internal.connection(gluegun_ws_test_current_process()),
            internal.stream(dynamic.string("socket-stream")),
            connection.Milliseconds(500),
          )

        websocket.ping(socket, <<"ping":utf8>>)
        |> expect.to_equal(Ok(Nil))

        capture_ws_send_message()
        |> expect.to_equal(Ok([#("ping", <<"ping":utf8>>)]))
      }),
      it("pong sends Pong through the wrapped connection and stream", fn() {
        let socket =
          websocket.socket(
            internal.connection(gluegun_ws_test_current_process()),
            internal.stream(dynamic.string("socket-stream")),
            connection.Milliseconds(500),
          )

        websocket.pong(socket, <<"pong":utf8>>)
        |> expect.to_equal(Ok(Nil))

        capture_ws_send_message()
        |> expect.to_equal(Ok([#("pong", <<"pong":utf8>>)]))
      }),
      it("close sends Close through the wrapped connection and stream", fn() {
        let socket =
          websocket.socket(
            internal.connection(gluegun_ws_test_current_process()),
            internal.stream(dynamic.string("socket-stream")),
            connection.Milliseconds(500),
          )

        websocket.close(socket)
        |> expect.to_equal(Ok(Nil))

        capture_ws_send_message()
        |> expect.to_equal(Ok([#("close", <<>>)]))
      }),
      it("receive_app_frame returns text frames", fn() {
        websocket.receive_app_frame_from([Ok(message.Text("hello"))], fn(_) {
          Ok(Nil)
        })
        |> expect.to_equal(Ok(message.Text("hello")))
      }),
      it("receive_app_frame returns binary frames", fn() {
        websocket.receive_app_frame_from(
          [Ok(message.Binary(<<1, 2, 3>>))],
          fn(_) { Ok(Nil) },
        )
        |> expect.to_equal(Ok(message.Binary(<<1, 2, 3>>)))
      }),
      it("receive_app_frame returns close frames", fn() {
        websocket.receive_app_frame_from([Ok(message.Close)], fn(_) { Ok(Nil) })
        |> expect.to_equal(Ok(message.Close))
      }),
      it("receive_app_frame returns close-with-reason frames", fn() {
        websocket.receive_app_frame_from(
          [Ok(message.CloseWithReason(1000, <<"bye":utf8>>))],
          fn(_) { Ok(Nil) },
        )
        |> expect.to_equal(Ok(message.CloseWithReason(1000, <<"bye":utf8>>)))
      }),
      it("receive_app_frame skips pong frames", fn() {
        websocket.receive_app_frame_from(
          [
            Ok(message.Pong(<<"ignored":utf8>>)),
            Ok(message.Text("after pong")),
          ],
          fn(_) { Ok(Nil) },
        )
        |> expect.to_equal(Ok(message.Text("after pong")))
      }),
      it(
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
      it("receive_app_frame returns pong send errors immediately", fn() {
        websocket.receive_app_frame_from(
          [
            Ok(message.Ping(<<"payload":utf8>>)),
            Ok(message.Text("unreached")),
          ],
          fn(_) { Error(error.StreamError("send failed")) },
        )
        |> expect.to_equal(Error(error.StreamError("send failed")))
      }),
    ]),
    describe("WebSocket session options", [
      it(
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
          |> decode.run(decode.dict(decode.string, decode.dynamic))
          |> result.map(dict.size)
          |> expect.to_equal(Ok(0))

          options
          |> websocket.options_timeout
          |> expect.to_equal(connection.Milliseconds(5000))
        },
      ),
      it("with_headers updates only headers", fn() {
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
      it("with_connect_options updates only connection options", fn() {
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
      it("with_upgrade_options updates only upgrade options", fn() {
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
        |> decode.run(decode.at(["compress"], decode.bool))
        |> expect.to_equal(Ok(True))

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
      it("with_timeout updates only timeout", fn() {
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
    describe("WebSocket session cleanup", [
      it("returns callback value when callback and cleanup succeed", fn() {
        websocket.with_socket_result(Ok("done"), Ok(Nil), Ok(Nil))
        |> expect.to_equal(Ok("done"))
      }),
      it("returns close-frame cleanup errors after callback success", fn() {
        websocket.with_socket_result(
          Ok("done"),
          Error(error.StreamError("close frame failed")),
          Ok(Nil),
        )
        |> expect.to_equal(Error(error.StreamError("close frame failed")))
      }),
      it("returns connection cleanup errors after callback success", fn() {
        websocket.with_socket_result(
          Ok("done"),
          Ok(Nil),
          Error(error.ConnectionError("connection close failed")),
        )
        |> expect.to_equal(
          Error(error.ConnectionError("connection close failed")),
        )
      }),
      it(
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
    describe("upgrade routing", [
      it("accepts upgrade messages", fn() {
        websocket.await_upgrade_from(Ok(message.Upgrade(["websocket"], [])))
        |> expect.to_equal(Ok(Nil))
      }),
      it("accepts upgrade messages with headers", fn() {
        websocket.await_upgrade_from(
          Ok(
            message.Upgrade(["websocket"], [#("sec-websocket-protocol", "chat")]),
          ),
        )
        |> expect.to_equal(Ok(Nil))
      }),
      it("rejects websocket frames while awaiting upgrade", fn() {
        websocket.await_upgrade_from(
          Ok(message.WebSocket(message.Text("oops"))),
        )
        |> expect.to_equal(
          Error(error.InvalidMessage(
            "websocket.await_upgrade: expected Upgrade message",
          )),
        )
      }),
      it("rejects HTTP responses while awaiting upgrade", fn() {
        websocket.await_upgrade_from(Ok(message.Response(fin.Fin, 101, [])))
        |> expect.to_equal(
          Error(error.InvalidMessage(
            "websocket.await_upgrade: expected Upgrade message",
          )),
        )
      }),
      it("propagates timeout while awaiting upgrade", fn() {
        websocket.await_upgrade_from(Error(error.Timeout))
        |> expect.to_equal(Error(error.Timeout))
      }),
      it("rejects HTTP/2 before calling FFI", fn() {
        let fake_conn = internal.connection(dynamic.string("not-a-pid"))
        websocket.upgrade_with_protocol(fake_conn, connection.Http2, "/ws", [])
        |> expect.to_equal(
          Error(error.InvalidMessage(
            "websocket.upgrade: WebSocket over HTTP/2 is not supported by Gun",
          )),
        )
      }),
      it("surfaces FFI errors from upgrade", fn() {
        // Gun does not support WebSocket over HTTP/2 (RFC 8441). That
        // limitation is documented in src/gluegun/websocket.gleam and the echo
        // example. This deterministic test does not create an HTTP/2 connection; it
        // verifies that errors raised by gun:ws_upgrade are surfaced as Result errors
        // rather than panicking or producing a misleading success.
        let fake_conn = internal.connection(dynamic.string("not-a-pid"))
        websocket.upgrade(fake_conn, "/ws", [])
        |> result.is_error
        |> expect.to_be_true
      }),
    ]),
    describe("WebSocket upgrade options", [
      it("encodes default options to an empty map", fn() {
        websocket.upgrade_options()
        |> websocket.upgrade_options_to_ffi
        |> decode.run(decode.dict(decode.string, decode.dynamic))
        |> result.map(dict.size)
        |> expect.to_equal(Ok(0))
      }),
      it("encodes typed Gun ws_opts fields", fn() {
        let options =
          websocket.upgrade_options()
          |> websocket.with_compress(True)
          |> websocket.with_silence_pings(True)
          |> websocket.with_flow(8)
          |> websocket.with_keepalive(connection.Milliseconds(30_000))
          |> websocket.with_closing_timeout(connection.Infinity)
        let ffi = websocket.upgrade_options_to_ffi(options)

        ffi
        |> decode.run(decode.at(["compress"], decode.bool))
        |> expect.to_equal(Ok(True))

        ffi
        |> decode.run(decode.at(["silence_pings"], decode.bool))
        |> expect.to_equal(Ok(True))

        ffi
        |> decode.run(decode.at(["flow"], decode.int))
        |> expect.to_equal(Ok(8))

        ffi
        |> decode.run(decode.at(["keepalive"], decode.int))
        |> expect.to_equal(Ok(30_000))

        ffi
        |> decode.run(decode.at(["closing_timeout"], atom.decoder()))
        |> expect.to_equal(Ok(atom.create("infinity")))
      }),
      it("preserves protocol module values", fn() {
        let ffi =
          websocket.upgrade_options()
          |> websocket.with_default_protocol_module("my_ws_h")
          |> websocket.with_protocol_module("chat", "chat_ws_h")
          |> websocket.upgrade_options_to_ffi

        ffi
        |> decode.run(decode.at(["default_protocol"], decode.string))
        |> expect.to_equal(Ok("my_ws_h"))

        ffi
        |> decode.run(decode.at(["protocols"], decode.list(protocol_decoder())))
        |> expect.to_equal(Ok([#("chat", "chat_ws_h")]))
      }),
      it("preserves dynamic reply_to, tunnel, and user_opts", fn() {
        let reply_to = dynamic.string("reply-target")
        let tunnel =
          dynamic.properties([
            #(dynamic.string("stream_ref"), dynamic.string("tunnel-stream")),
          ])
        let user_opts = dynamic.list([dynamic.int(1), dynamic.string("two")])

        let ffi =
          websocket.upgrade_options()
          |> websocket.with_reply_to_dynamic(reply_to)
          |> websocket.with_tunnel_dynamic(tunnel)
          |> websocket.with_user_opts_dynamic(user_opts)
          |> websocket.upgrade_options_to_ffi

        ffi
        |> decode.run(decode.at(["reply_to"], decode.dynamic))
        |> expect.to_equal(Ok(reply_to))

        ffi
        |> decode.run(decode.at(["tunnel"], decode.dynamic))
        |> expect.to_equal(Ok(tunnel))

        ffi
        |> decode.run(decode.at(["user_opts"], decode.dynamic))
        |> expect.to_equal(Ok(user_opts))
      }),
      it("normalizes typed options before calling Gun", fn() {
        let options =
          websocket.upgrade_options()
          |> websocket.with_compress(True)
          |> websocket.with_silence_pings(False)
          |> websocket.with_flow(16)
          |> websocket.with_keepalive(connection.Milliseconds(45_000))
          |> websocket.with_closing_timeout(connection.Infinity)
          |> websocket.upgrade_options_to_ffi

        let assert Ok(captured) = capture_ws_upgrade_options(options)

        captured
        |> decode.run(decode.at(["compress"], decode.bool))
        |> expect.to_equal(Ok(True))

        captured
        |> decode.run(decode.at(["silence_pings"], decode.bool))
        |> expect.to_equal(Ok(False))

        captured
        |> decode.run(decode.at(["flow"], decode.int))
        |> expect.to_equal(Ok(16))

        captured
        |> decode.run(decode.at(["keepalive"], decode.int))
        |> expect.to_equal(Ok(45_000))

        captured
        |> decode.run(decode.at(["closing_timeout"], atom.decoder()))
        |> result.map(atom.to_string)
        |> expect.to_equal(Ok("infinity"))
      }),
      it("normalizes protocol modules before calling Gun", fn() {
        let options =
          websocket.upgrade_options()
          |> websocket.with_default_protocol_module("gluegun_ws_test")
          |> websocket.with_protocol_module("chat", "gluegun_ws_test")
          |> websocket.upgrade_options_to_ffi

        let assert Ok(captured) = capture_ws_upgrade_options(options)

        captured
        |> decode.run(decode.at(["default_protocol"], atom.decoder()))
        |> result.map(atom.to_string)
        |> expect.to_equal(Ok("gluegun_ws_test"))

        captured
        |> decode.run(decode.at(
          ["protocols"],
          decode.list(gun_protocol_decoder()),
        ))
        |> expect.to_equal(Ok([#("chat", "gluegun_ws_test")]))
      }),
      it("rejects unknown default protocol modules before calling Gun", fn() {
        let options =
          websocket.upgrade_options()
          |> websocket.with_default_protocol_module(
            "gluegun_nonexistent_ws_handler",
          )
          |> websocket.upgrade_options_to_ffi

        capture_ws_upgrade_options(options)
        |> result.map_error(error.decode_ffi_error)
        |> expect.to_equal(
          Error(error.InvalidOptions(
            "Ws(UnknownModule(\"gluegun_nonexistent_ws_handler\"))",
          )),
        )
      }),
      it("rejects unknown protocol modules before calling Gun", fn() {
        let options =
          websocket.upgrade_options()
          |> websocket.with_protocol_module(
            "chat",
            "gluegun_nonexistent_protocol_ws_handler",
          )
          |> websocket.upgrade_options_to_ffi

        capture_ws_upgrade_options(options)
        |> result.map_error(error.decode_ffi_error)
        |> expect.to_equal(
          Error(error.InvalidOptions(
            "Ws(UnknownModule(\"gluegun_nonexistent_protocol_ws_handler\"))",
          )),
        )
      }),
      it("returns InvalidOptions for invalid Gun ws_opts", fn() {
        gluegun_ws_test_invalid_ws_upgrade_options_result()
        |> result.map_error(error.decode_ffi_error)
        |> expect.to_equal(Error(error.InvalidOptions("Ws(Compress)")))
      }),
      it("rejects unsupported FFI ws_opts before Gun validation", fn() {
        gluegun_ws_test_invalid_ws_upgrade_unknown_option_result()
        |> result.map_error(error.decode_ffi_error)
        |> expect.to_equal(
          Error(error.InvalidOptions(
            "Ws(UnsupportedOption(\"unexpected_ws_option\"))",
          )),
        )
      }),
    ]),
  ])
}

// ── Helpers ──────────────────────────────────────────────────────────────────

fn make_ws_frame_map(
  frame_type: String,
  extra: List(#(String, dynamic.Dynamic)),
) -> dynamic.Dynamic {
  let frame_fields =
    list.append(
      [#(dynamic.string("type"), dynamic.string(frame_type))],
      list.map(extra, fn(pair) { #(dynamic.string(pair.0), pair.1) }),
    )
  let frame = dynamic.properties(frame_fields)
  dynamic.properties([
    #(dynamic.string("type"), dynamic.string("websocket")),
    #(dynamic.string("frame"), frame),
  ])
}

fn protocol_decoder() -> decode.Decoder(#(String, String)) {
  decode.then(decode.at([0], decode.string), fn(protocol) {
    decode.map(decode.at([1], decode.string), fn(module_name) {
      #(protocol, module_name)
    })
  })
}

fn gun_protocol_decoder() -> decode.Decoder(#(String, String)) {
  decode.then(decode.at([0], decode.string), fn(protocol) {
    decode.map(decode.at([1], atom.decoder()), fn(module_name) {
      #(protocol, atom.to_string(module_name))
    })
  })
}

@external(erlang, "gluegun_ws_test", "test_close_plain_message")
fn gluegun_ws_test_close_plain_message() -> dynamic.Dynamic

@external(erlang, "gluegun_ws_test", "capture_ws_send_frame_message")
fn capture_ws_send_frame_message(
  frame: message.Frame,
) -> Result(dynamic.Dynamic, dynamic.Dynamic)

@external(erlang, "gluegun_ws_test", "capture_ws_send_message")
fn capture_ws_send_message() -> Result(List(#(String, BitArray)), Nil)

@external(erlang, "gluegun_ws_test", "capture_ws_upgrade_options")
fn capture_ws_upgrade_options(
  options: dynamic.Dynamic,
) -> Result(dynamic.Dynamic, dynamic.Dynamic)

@external(erlang, "gluegun_ws_test", "current_process")
fn gluegun_ws_test_current_process() -> dynamic.Dynamic

@external(erlang, "gluegun_ws_test", "invalid_ws_send_frame_result")
fn gluegun_ws_test_invalid_ws_send_frame_result() -> Result(
  dynamic.Dynamic,
  dynamic.Dynamic,
)

@external(erlang, "gluegun_ws_test", "invalid_ws_send_frame_list_result")
fn gluegun_ws_test_invalid_ws_send_frame_list_result() -> Result(
  dynamic.Dynamic,
  dynamic.Dynamic,
)

@external(erlang, "gluegun_ws_test", "invalid_ws_send_text_utf8_result")
fn gluegun_ws_test_invalid_ws_send_text_utf8_result() -> Result(
  dynamic.Dynamic,
  dynamic.Dynamic,
)

@external(erlang, "gluegun_ws_test", "invalid_ws_upgrade_options_result")
fn gluegun_ws_test_invalid_ws_upgrade_options_result() -> Result(
  dynamic.Dynamic,
  dynamic.Dynamic,
)

@external(erlang, "gluegun_ws_test", "invalid_ws_upgrade_unknown_option_result")
fn gluegun_ws_test_invalid_ws_upgrade_unknown_option_result() -> Result(
  dynamic.Dynamic,
  dynamic.Dynamic,
)

@external(erlang, "gluegun_ws_test", "test_close_with_reason_message")
fn gluegun_ws_test_close_with_reason_message() -> dynamic.Dynamic

@external(erlang, "gluegun_ws_test", "test_ws_close_gun_tuple")
fn gluegun_ws_test_ws_close_gun_tuple() -> dynamic.Dynamic

@external(erlang, "gluegun_ws_test", "test_ws_close_with_reason_gun_tuple")
fn gluegun_ws_test_ws_close_with_reason_gun_tuple() -> dynamic.Dynamic

@external(erlang, "gluegun_ffi", "safe_message_to_map")
fn gluegun_ffi_safe_message_to_map(
  message: dynamic.Dynamic,
) -> Result(dynamic.Dynamic, dynamic.Dynamic)
