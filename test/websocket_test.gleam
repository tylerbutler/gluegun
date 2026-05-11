/// Tests for WebSocket support: frame encoding/decoding, receive routing,
/// await_upgrade routing, and FFI shape validation.
///
/// Tests can be filtered with `gleam test -- --test-name-filter=WebSocket`
/// or by file path with `gleam test -- test/websocket_test.gleam`.
import gleam/dynamic
import gleam/list
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

@external(erlang, "gluegun_ws_test", "test_close_plain_message")
fn gluegun_ws_test_close_plain_message() -> dynamic.Dynamic

@external(erlang, "gluegun_ws_test", "capture_ws_send_frame_message")
fn capture_ws_send_frame_message(
  frame: message.Frame,
) -> Result(dynamic.Dynamic, dynamic.Dynamic)

@external(erlang, "gluegun_ws_test", "capture_ws_send_message")
fn capture_ws_send_message() -> Result(List(#(String, BitArray)), Nil)

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
