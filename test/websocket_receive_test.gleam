import gluegun/connection
import gluegun/error
import gluegun/message
import gluegun/request
import gluegun/websocket

pub fn decodes_empty_ping_atom_through_mailbox_and_await_test() -> Nil {
  assert_decoded(empty_ping_frame(), message.Ping(<<>>))
}

pub fn decodes_empty_pong_atom_through_mailbox_and_await_test() -> Nil {
  assert_decoded(empty_pong_frame(), message.Pong(<<>>))
}

pub fn decodes_empty_ping_tuple_through_mailbox_and_await_test() -> Nil {
  assert_decoded(ping_frame(<<>>), message.Ping(<<>>))
}

pub fn decodes_empty_pong_tuple_through_mailbox_and_await_test() -> Nil {
  assert_decoded(pong_frame(<<>>), message.Pong(<<>>))
}

pub fn decodes_nonempty_ping_tuple_through_mailbox_and_await_test() -> Nil {
  assert_decoded(ping_frame(<<0, 255>>), message.Ping(<<0, 255>>))
}

pub fn decodes_nonempty_pong_tuple_through_mailbox_and_await_test() -> Nil {
  assert_decoded(pong_frame(<<0, 255>>), message.Pong(<<0, 255>>))
}

pub fn skips_empty_controls_before_binary_frame_test() -> Nil {
  equal(
    websocket.receive_app_frame_from([
      Ok(message.Ping(<<>>)),
      Ok(message.Pong(<<>>)),
      Ok(message.Binary(<<0, 255>>)),
    ]),
    Ok(message.Binary(<<0, 255>>)),
  )
}

pub fn zero_application_budget_preserves_queued_frames_test() -> Nil {
  let #(connection, stream) = queue_control_frame()
  let assert Ok(zero) = connection.milliseconds(0)
  let socket = websocket.socket(connection, stream, zero)
  let assert Error(error.Timeout) = websocket.receive_app_frame(socket)
  let assert Ok(wait) = connection.milliseconds(500)
  let assert Ok(message.WebSocket(message.Ping(<<>>))) =
    message.await(connection, stream, wait)
  Nil
}

pub fn visible_controls_do_not_restart_the_application_deadline_test() -> Nil {
  let assert Ok(Nil) =
    with_control_frames(500, fn(port) {
      let assert Ok(wait) = connection.milliseconds(100)
      let assert Ok(socket) = connect_with_controls(port, wait)
      let #(received, elapsed) =
        timed(fn() { websocket.receive_app_frame(socket) })
      let cleanup = websocket.close(socket)
      let assert Error(error.Timeout) = received
      let assert True = elapsed >= 75 && elapsed < 350
      cleanup
    })
  Nil
}

pub fn unlimited_application_wait_skips_controls_until_text_arrives_test() -> Nil {
  let assert Ok(Nil) =
    with_control_frames(500, fn(port) {
      let assert Ok(socket) = connect_with_controls(port, connection.infinity())
      let #(received, elapsed) =
        timed(fn() { websocket.receive_app_frame(socket) })
      let cleanup = websocket.close(socket)
      let assert Ok(message.Text("late text")) = received
      let assert True = elapsed >= 450
      cleanup
    })
  Nil
}

fn connect_with_controls(
  port: Int,
  timeout: connection.Timeout,
) -> Result(websocket.Socket, error.GluegunError) {
  websocket.connect(
    host: "127.0.0.1",
    port: port,
    path: "/",
    options: websocket.options()
      |> websocket.with_timeout(timeout)
      |> websocket.with_upgrade_options(
        websocket.upgrade_options()
        |> websocket.with_silence_pings(False),
      ),
  )
}

pub fn skips_controls_before_close_frame_test() -> Nil {
  equal(
    websocket.receive_app_frame_from([
      Ok(message.Ping(<<"ping":utf8>>)),
      Ok(message.Pong(<<>>)),
      Ok(message.Close),
    ]),
    Ok(message.Close),
  )
}

pub fn skips_controls_before_close_with_reason_frame_test() -> Nil {
  let frame = message.CloseWithReason(1000, <<"done":utf8>>)
  equal(
    websocket.receive_app_frame_from([
      Ok(message.Ping(<<>>)),
      Ok(message.Pong(<<"pong":utf8>>)),
      Ok(frame),
    ]),
    Ok(frame),
  )
}

pub fn reports_missing_application_frame_after_controls_test() -> Nil {
  equal(
    websocket.receive_app_frame_from([
      Ok(message.Ping(<<>>)),
      Ok(message.Pong(<<>>)),
    ]),
    Error(error.InvalidMessage(
      "websocket.receive_app_frame: expected WebSocket application frame",
    )),
  )
}

pub fn default_silenced_empty_controls_send_one_pong_test() -> Nil {
  with_incoming_controls_default(<<>>, receive_application_frames)
}

pub fn default_silenced_controls_send_one_pong_test() -> Nil {
  with_incoming_controls_default(<<0, 255>>, receive_application_frames)
}

pub fn visible_empty_controls_send_one_pong_test() -> Nil {
  with_incoming_controls(False, <<>>, receive_application_frames)
}

pub fn visible_controls_send_one_pong_test() -> Nil {
  with_incoming_controls(False, <<0, 255>>, receive_application_frames)
}

pub fn explicitly_silenced_empty_controls_send_one_pong_test() -> Nil {
  with_incoming_controls(True, <<>>, receive_application_frames)
}

pub fn explicitly_silenced_controls_send_one_pong_test() -> Nil {
  with_incoming_controls(True, <<0, 255>>, receive_application_frames)
}

pub fn loopback_cleanup_preserves_unrelated_messages_after_success_test() -> Nil {
  assert_cleanup_success()
}

pub fn loopback_cleanup_preserves_unrelated_messages_after_callback_failure_test() -> Nil {
  assert_cleanup_callback_failure()
}

fn receive_application_frames(
  connection: connection.Connection,
  stream: request.Stream,
) -> Nil {
  let assert Ok(timeout) = connection.milliseconds(5000)
  let socket = websocket.socket(connection, stream, timeout)
  equal(websocket.receive_app_frame(socket), Ok(message.Text("hello")))
  equal(websocket.receive_app_frame(socket), Ok(message.Binary(<<1, 2, 3>>)))
  let assert Ok(Nil) = websocket.send_text(socket, "controls received")
  equal(websocket.receive_app_frame(socket), Ok(message.Text("one pong")))
}

fn assert_decoded(raw_frame: GunFrame, frame: message.Frame) -> Nil {
  let connection = current_connection()
  let stream = stream_ref()
  let assert Ok(envelope) =
    message.decode(mailbox_websocket_frame_message(
      connection,
      stream,
      raw_frame,
    ))
  equal(envelope.connection, connection)
  equal(envelope.stream, stream)
  equal(envelope.message, message.WebSocket(frame))
  equal(
    safe_decode_message(websocket_frame_message(raw_frame)),
    Ok(message.WebSocket(frame)),
  )
}

fn equal(actual: a, expected: a) -> Nil {
  let assert #(True, _, _) = #(actual == expected, actual, expected)
  Nil
}

type GunFrame

@external(erlang, "gluegun_ws_receive_test", "empty_ping_frame")
fn empty_ping_frame() -> GunFrame

@external(erlang, "gluegun_ws_close_test", "queue_control_frame")
fn queue_control_frame() -> #(connection.Connection, request.Stream)

@external(erlang, "gluegun_ws_close_test", "with_control_frames")
fn with_control_frames(
  duration: Int,
  callback: fn(Int) -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ws_close_test", "timed")
fn timed(callback: fn() -> a) -> #(a, Int)

@external(erlang, "gluegun_ws_receive_test", "empty_pong_frame")
fn empty_pong_frame() -> GunFrame

@external(erlang, "gluegun_ffi_test", "ping_frame")
fn ping_frame(data: BitArray) -> GunFrame

@external(erlang, "gluegun_ffi_test", "pong_frame")
fn pong_frame(data: BitArray) -> GunFrame

@external(erlang, "gluegun_ffi_test", "current_connection")
fn current_connection() -> connection.Connection

@external(erlang, "gluegun_ffi_test", "stream_ref")
fn stream_ref() -> request.Stream

@external(erlang, "gluegun_ffi_test", "mailbox_websocket_frame_message")
fn mailbox_websocket_frame_message(
  connection: connection.Connection,
  stream: request.Stream,
  frame: GunFrame,
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "websocket_frame_message")
fn websocket_frame_message(frame: GunFrame) -> message.GunMessage

@external(erlang, "gluegun_ffi", "safe_decode_message")
fn safe_decode_message(
  message: message.GunMessage,
) -> Result(message.Message, error.GluegunError)

@external(erlang, "gluegun_ws_control_test", "with_incoming_controls")
fn with_incoming_controls(
  silence_pings: Bool,
  payload: BitArray,
  callback: fn(connection.Connection, request.Stream) -> Nil,
) -> Nil

@external(erlang, "gluegun_ws_control_test", "with_incoming_controls_default")
fn with_incoming_controls_default(
  payload: BitArray,
  callback: fn(connection.Connection, request.Stream) -> Nil,
) -> Nil

@external(erlang, "gluegun_ws_receive_test", "assert_cleanup_success")
fn assert_cleanup_success() -> Nil

@external(erlang, "gluegun_ws_receive_test", "assert_cleanup_callback_failure")
fn assert_cleanup_callback_failure() -> Nil
