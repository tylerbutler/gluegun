/// Tests for WebSocket support: frame encoding/decoding, receive routing,
/// await_upgrade routing, and FFI shape validation.
///
/// Tests are filtered with `gleam test -- --filter "websocket"`.
import gleam/dynamic
import gleam/list
import gleam/result
import gleeunit/should
import gluegun/error
import gluegun/internal
import gluegun/message
import gluegun/websocket

// ── Frame type variants ──────────────────────────────────────────────────────

pub fn websocket_frame_close_zero_arg_variant_test() {
  let frame: message.Frame = message.Close
  frame |> should.equal(message.Close)
}

pub fn websocket_frame_close_with_reason_variant_test() {
  let frame: message.Frame =
    message.CloseWithReason(1000, <<"normal closure":utf8>>)
  frame
  |> should.equal(message.CloseWithReason(1000, <<"normal closure":utf8>>))
}

// ── Outbound frame encoding ──────────────────────────────────────────────────

pub fn websocket_encode_text_frame_test() {
  capture_ws_send_frame_message(message.Text("hello"))
  |> result.map_error(error.decode_ffi_error)
  |> result.try(message.decode)
  |> should.equal(Ok(message.WebSocket(message.Text("hello"))))
}

pub fn websocket_encode_binary_frame_test() {
  capture_ws_send_frame_message(message.Binary(<<0, 1, 2, 255>>))
  |> result.map_error(error.decode_ffi_error)
  |> result.try(message.decode)
  |> should.equal(Ok(message.WebSocket(message.Binary(<<0, 1, 2, 255>>))))
}

pub fn websocket_encode_ping_frame_test() {
  capture_ws_send_frame_message(message.Ping(<<"ping":utf8>>))
  |> result.map_error(error.decode_ffi_error)
  |> result.try(message.decode)
  |> should.equal(Ok(message.WebSocket(message.Ping(<<"ping":utf8>>))))
}

pub fn websocket_encode_pong_frame_test() {
  capture_ws_send_frame_message(message.Pong(<<"pong":utf8>>))
  |> result.map_error(error.decode_ffi_error)
  |> result.try(message.decode)
  |> should.equal(Ok(message.WebSocket(message.Pong(<<"pong":utf8>>))))
}

pub fn websocket_encode_close_plain_frame_test() {
  capture_ws_send_frame_message(message.Close)
  |> result.map_error(error.decode_ffi_error)
  |> result.try(message.decode)
  |> should.equal(Ok(message.WebSocket(message.Close)))
}

pub fn websocket_encode_close_with_reason_frame_test() {
  capture_ws_send_frame_message(
    message.CloseWithReason(1000, <<"normal closure":utf8>>),
  )
  |> result.map_error(error.decode_ffi_error)
  |> result.try(message.decode)
  |> should.equal(
    Ok(
      message.WebSocket(
        message.CloseWithReason(1000, <<"normal closure":utf8>>),
      ),
    ),
  )
}

// ── Inbound frame decoding ───────────────────────────────────────────────────

pub fn websocket_decode_text_frame_test() {
  make_ws_frame_map("text", [#("data", dynamic.string("hello world"))])
  |> message.decode
  |> should.equal(Ok(message.WebSocket(message.Text("hello world"))))
}

pub fn websocket_decode_binary_frame_test() {
  make_ws_frame_map("binary", [#("data", dynamic.bit_array(<<0, 1, 2, 255>>))])
  |> message.decode
  |> should.equal(Ok(message.WebSocket(message.Binary(<<0, 1, 2, 255>>))))
}

pub fn websocket_decode_ping_frame_test() {
  make_ws_frame_map("ping", [#("data", dynamic.bit_array(<<>>))])
  |> message.decode
  |> should.equal(Ok(message.WebSocket(message.Ping(<<>>))))
}

pub fn websocket_decode_pong_frame_test() {
  make_ws_frame_map("pong", [#("data", dynamic.bit_array(<<"keepalive":utf8>>))])
  |> message.decode
  |> should.equal(Ok(message.WebSocket(message.Pong(<<"keepalive":utf8>>))))
}

pub fn websocket_decode_close_plain_frame_test() {
  make_ws_frame_map("close", [])
  |> message.decode
  |> should.equal(Ok(message.WebSocket(message.Close)))
}

pub fn websocket_decode_close_with_reason_frame_test() {
  make_ws_frame_map("close_with_reason", [
    #("code", dynamic.int(1001)),
    #("reason", dynamic.bit_array(<<"going away":utf8>>)),
  ])
  |> message.decode
  |> should.equal(
    Ok(message.WebSocket(message.CloseWithReason(1001, <<"going away":utf8>>))),
  )
}

// ── FFI close frame shape (safe_message_to_map produces new format) ──────────

pub fn websocket_ffi_close_plain_decodes_to_close_test() {
  gluegun_ws_test_close_plain_message()
  |> message.decode
  |> should.equal(Ok(message.WebSocket(message.Close)))
}

pub fn websocket_ffi_close_with_reason_decodes_to_close_with_reason_test() {
  gluegun_ws_test_close_with_reason_message()
  |> message.decode
  |> should.equal(
    Ok(message.WebSocket(message.CloseWithReason(1001, <<"going away":utf8>>))),
  )
}

pub fn websocket_safe_message_to_map_close_plain_test() {
  gluegun_ws_test_ws_close_gun_tuple()
  |> gluegun_ffi_safe_message_to_map
  |> result.map_error(error.decode_ffi_error)
  |> result.try(message.decode)
  |> should.equal(Ok(message.WebSocket(message.Close)))
}

pub fn websocket_safe_message_to_map_close_with_reason_test() {
  gluegun_ws_test_ws_close_with_reason_gun_tuple()
  |> gluegun_ffi_safe_message_to_map
  |> result.map_error(error.decode_ffi_error)
  |> result.try(message.decode)
  |> should.equal(
    Ok(message.WebSocket(message.CloseWithReason(1001, <<"going away":utf8>>))),
  )
}

// ── websocket.receive_from routing ──────────────────────────────────────────

pub fn websocket_receive_from_accepts_websocket_text_test() {
  websocket.receive_from(Ok(message.WebSocket(message.Text("hi"))))
  |> should.equal(Ok(message.Text("hi")))
}

pub fn websocket_receive_from_accepts_websocket_binary_test() {
  websocket.receive_from(Ok(message.WebSocket(message.Binary(<<1, 2, 3>>))))
  |> should.equal(Ok(message.Binary(<<1, 2, 3>>)))
}

pub fn websocket_receive_from_accepts_websocket_close_test() {
  websocket.receive_from(Ok(message.WebSocket(message.Close)))
  |> should.equal(Ok(message.Close))
}

pub fn websocket_receive_from_accepts_websocket_close_with_reason_test() {
  websocket.receive_from(
    Ok(message.WebSocket(message.CloseWithReason(1000, <<"bye":utf8>>))),
  )
  |> should.equal(Ok(message.CloseWithReason(1000, <<"bye":utf8>>)))
}

pub fn websocket_receive_from_rejects_http_response_test() {
  websocket.receive_from(Ok(message.Response(message.Fin, 200, [])))
  |> should.equal(
    Error(error.InvalidMessage(
      "websocket.receive: expected WebSocket frame, got HTTP message",
    )),
  )
}

pub fn websocket_receive_from_rejects_http_data_test() {
  websocket.receive_from(Ok(message.Data(message.Fin, <<"body":utf8>>)))
  |> should.equal(
    Error(error.InvalidMessage(
      "websocket.receive: expected WebSocket frame, got HTTP message",
    )),
  )
}

pub fn websocket_receive_from_rejects_upgrade_message_test() {
  websocket.receive_from(Ok(message.Upgrade(["websocket"], [])))
  |> should.equal(
    Error(error.InvalidMessage(
      "websocket.receive: expected WebSocket frame, got Upgrade message; call await_upgrade first",
    )),
  )
}

pub fn websocket_receive_from_propagates_timeout_test() {
  websocket.receive_from(Error(error.Timeout))
  |> should.equal(Error(error.Timeout))
}

pub fn websocket_receive_from_propagates_stream_error_test() {
  websocket.receive_from(Error(error.StreamError("closed")))
  |> should.equal(Error(error.StreamError("closed")))
}

// ── websocket.await_upgrade_from routing ────────────────────────────────────

pub fn websocket_await_upgrade_from_accepts_upgrade_test() {
  websocket.await_upgrade_from(Ok(message.Upgrade(["websocket"], [])))
  |> should.equal(Ok(Nil))
}

pub fn websocket_await_upgrade_from_accepts_upgrade_with_headers_test() {
  websocket.await_upgrade_from(
    Ok(message.Upgrade(["websocket"], [#("sec-websocket-protocol", "chat")])),
  )
  |> should.equal(Ok(Nil))
}

pub fn websocket_await_upgrade_from_rejects_websocket_frame_test() {
  websocket.await_upgrade_from(Ok(message.WebSocket(message.Text("oops"))))
  |> should.equal(
    Error(error.InvalidMessage(
      "websocket.await_upgrade: expected Upgrade message",
    )),
  )
}

pub fn websocket_await_upgrade_from_rejects_http_response_test() {
  websocket.await_upgrade_from(Ok(message.Response(message.Fin, 101, [])))
  |> should.equal(
    Error(error.InvalidMessage(
      "websocket.await_upgrade: expected Upgrade message",
    )),
  )
}

pub fn websocket_await_upgrade_from_propagates_timeout_test() {
  websocket.await_upgrade_from(Error(error.Timeout))
  |> should.equal(Error(error.Timeout))
}

// ── HTTP/2 WebSocket unsupported ─────────────────────────────────────────────

pub fn websocket_upgrade_surfaces_ffi_errors_test() {
  // Gun does not support WebSocket over HTTP/2 (RFC 8441). That
  // limitation is documented in src/gluegun/websocket.gleam and the echo
  // example. This deterministic test does not create an HTTP/2 connection; it
  // verifies that errors raised by gun:ws_upgrade are surfaced as Result errors
  // rather than panicking or producing a misleading success.
  let fake_conn = internal.connection(dynamic.string("not-a-pid"))
  websocket.upgrade(fake_conn, "/ws", [])
  |> result.is_error
  |> should.be_true
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
