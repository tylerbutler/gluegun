import gluegun/connection
import gluegun/error
import gluegun/message
import gluegun/request
import gluegun/websocket

pub fn raw_override_timeout_keeps_socket_usable_and_default_unchanged_test() -> Nil {
  assert_reusable_after_timeout(False)
}

pub fn application_override_timeout_keeps_socket_usable_and_default_unchanged_test() -> Nil {
  assert_reusable_after_timeout(True)
}

fn assert_reusable_after_timeout(application: Bool) -> Nil {
  let assert Ok(Nil) =
    with_server("normal", fn(port) {
      let assert Ok(socket) = connect(port, websocket.upgrade_options())
      let assert Ok(owner) = owned_connection()
      let #(received, elapsed) =
        timed(fn() { receive_within(socket, timeout(25), application) })
      let assert Error(error.Timeout) = received
      let assert True = elapsed >= 15 && elapsed < 350
      let assert Ok(Nil) = websocket.send_text(socket, "after timeout")
      let assert Ok(message.Text("after timeout")) =
        receive_within(socket, timeout(500), application)
      assert_default_timeout(socket, application)
      let assert Ok(Nil) = websocket.close(socket)
      assert_released(owner)
    })
  Nil
}

pub fn long_finite_application_override_keeps_short_default_test() -> Nil {
  assert_long_application_receive(timeout(1500))
}

pub fn infinite_application_override_keeps_short_default_test() -> Nil {
  assert_long_application_receive(connection.infinity())
}

fn assert_long_application_receive(wait: connection.Timeout) -> Nil {
  let assert Ok(Nil) =
    with_control_frames(500, fn(port) {
      // Setup and the socket's default receive/close budget stay at 100ms.
      let assert Ok(socket) =
        connect(
          port,
          websocket.upgrade_options()
            |> websocket.with_silence_pings(False),
        )
      let assert Ok(owner) = owned_connection()
      let #(received, elapsed) =
        timed(fn() { websocket.receive_app_frame_within(socket, wait) })
      let assert Ok(message.Text("late text")) = received
      let assert True = elapsed >= 450 && elapsed < 2000
      assert_default_timeout(socket, True)
      let assert Ok(Nil) = websocket.close(socket)
      assert_released(owner)
    })
  Nil
}

pub fn controls_do_not_restart_the_override_application_deadline_test() -> Nil {
  let assert Ok(Nil) =
    with_control_frames(500, fn(port) {
      let assert Ok(socket) =
        connect(
          port,
          websocket.upgrade_options()
            |> websocket.with_silence_pings(False),
        )
      let assert Ok(owner) = owned_connection()
      let #(received, elapsed) =
        timed(fn() { websocket.receive_app_frame_within(socket, timeout(150)) })
      let assert Error(error.Timeout) = received
      let assert True = elapsed >= 125 && elapsed < 350
      let assert Ok(message.Text("late text")) =
        websocket.receive_app_frame_within(socket, timeout(1000))
      let assert Ok(Nil) = websocket.close(socket)
      assert_released(owner)
    })
  Nil
}

pub fn long_application_override_does_not_extend_stalled_close_test() -> Nil {
  let assert Ok(Nil) =
    with_server("stall", fn(port) {
      let assert Ok(socket) = connect(port, websocket.upgrade_options())
      let assert Ok(owner) = owned_connection()
      let #(received, receive_elapsed) =
        timed(fn() { websocket.receive_app_frame_within(socket, timeout(500)) })
      let assert Error(error.Timeout) = received
      let assert True = receive_elapsed >= 450 && receive_elapsed < 1500
      let #(closed, close_elapsed) = timed(fn() { websocket.close(socket) })
      let assert Error(error.Timeout) = closed
      let assert True = close_elapsed >= 75 && close_elapsed < 350
      assert_released(owner)
    })
  Nil
}

pub fn zero_application_override_preserves_a_queued_control_for_raw_zero_test() -> Nil {
  let #(owner, stream) = queue_control_frame()
  let socket = websocket.socket(owner, stream, timeout(100))
  let assert Error(error.Timeout) =
    websocket.receive_app_frame_within(socket, timeout(0))
  let assert Ok(message.Ping(<<>>)) =
    websocket.receive_frame_within(socket, timeout(0))
  let assert Error(error.Timeout) =
    websocket.receive_frame_within(socket, timeout(0))
  Nil
}

pub fn finite_credit_pauses_and_replenishes_subsequent_traffic_test() -> Nil {
  let assert Ok(upgrade) = websocket.upgrade_options() |> websocket.with_flow(1)
  let assert Ok(Nil) =
    with_server("normal", fn(port) {
      let assert Ok(socket) = connect(port, upgrade)
      let assert Ok(owner) = owned_connection()
      // Request the first frame after upgrade so buffered data cannot bypass credit.
      let assert Ok(Nil) = websocket.send_text(socket, "one")
      let assert Ok(message.Text("one")) =
        websocket.receive_frame_within(socket, timeout(500))
      let assert Ok(Nil) = websocket.send_text(socket, "two")
      let assert Error(error.Timeout) =
        websocket.receive_app_frame_within(socket, timeout(100))
      let assert Ok(Nil) = websocket.update_flow(socket, 1)
      let assert Ok(message.Text("two")) =
        websocket.receive_app_frame_within(socket, timeout(500))
      let assert Ok(Nil) = websocket.send_text(socket, "three")
      let assert Error(error.Timeout) =
        websocket.receive_frame_within(socket, timeout(100))
      let assert Ok(Nil) = websocket.update_flow(socket, 1)
      let assert Ok(message.Text("three")) =
        websocket.receive_frame_within(socket, timeout(500))
      let assert Ok(Nil) = websocket.close(socket)
      assert_released(owner)
    })
  Nil
}

pub fn flow_update_preserves_skipped_visible_controls_credit_for_close_test() -> Nil {
  let assert Ok(upgrade) =
    websocket.upgrade_options()
    |> websocket.with_silence_pings(False)
    |> websocket.with_flow(1)
  let assert Ok(Nil) =
    with_server("flow_controls", fn(port) {
      let assert Ok(socket) = connect(port, upgrade)
      let assert Ok(owner) = owned_connection()
      let assert Error(error.Timeout) =
        websocket.receive_app_frame_within(socket, timeout(100))
      let assert Ok(Nil) = websocket.update_flow(socket, 1)
      let assert Error(error.Timeout) =
        websocket.receive_app_frame_within(socket, timeout(100))
      // Adding one leaves zero credit; close must reimburse skipped controls.
      let assert Ok(Nil) = websocket.close(socket)
      assert_released(owner)
    })
  Nil
}

pub fn zero_flow_increment_returns_exact_error_without_a_cast_test() -> Nil {
  assert_invalid_increment(0)
}

pub fn negative_flow_increment_returns_exact_error_without_a_cast_test() -> Nil {
  assert_invalid_increment(-1)
}

fn assert_invalid_increment(increment: Int) -> Nil {
  let socket =
    websocket.socket(current_connection(), stream_ref(), timeout(100))
  let actual = websocket.update_flow(socket, increment)
  // Inspect casts before asserting the result, so an erroneous cast is drained.
  let clean = no_flow_cast()
  let expected =
    Error(error.InvalidOptions("flow-control increment must be positive"))
  let assert #(True, _, _) = #(actual == expected, actual, expected)
  let assert True = clean
  Nil
}

pub fn positive_flow_increment_cast_carries_the_socket_stream_test() -> Nil {
  let owner = current_connection()
  let stream = stream_ref()
  let socket = websocket.socket(owner, stream, timeout(100))
  let assert Ok(Nil) = websocket.update_flow(socket, 7)
  let assert Ok(cast) = capture_update_flow()
  let expected = #(owner, stream, 7)
  let assert #(True, _, _) = #(cast == expected, cast, expected)
  let assert True = no_flow_cast()
  Nil
}

pub fn raw_override_tracks_peer_close_test() -> Nil {
  assert_peer_close("peer_close", False, message.Close)
}

pub fn raw_override_tracks_peer_close_with_reason_test() -> Nil {
  assert_peer_close(
    "peer_reason",
    False,
    message.CloseWithReason(1000, <<"bye":utf8>>),
  )
}

pub fn application_override_tracks_peer_close_test() -> Nil {
  assert_peer_close("peer_close", True, message.Close)
}

pub fn application_override_tracks_peer_close_with_reason_test() -> Nil {
  assert_peer_close(
    "peer_reason",
    True,
    message.CloseWithReason(1000, <<"bye":utf8>>),
  )
}

fn assert_peer_close(
  mode: String,
  application: Bool,
  expected: message.Frame,
) -> Nil {
  let assert Ok(Nil) =
    with_server(mode, fn(port) {
      let assert Ok(socket) = connect(port, websocket.upgrade_options())
      let assert Ok(owner) = owned_connection()
      let received = receive_within(socket, timeout(500), application)
      let assert #(True, _, _) = #(received == Ok(expected), received, expected)
      let assert Ok(Nil) = websocket.close(socket)
      let assert Ok(Nil) = websocket.close(socket)
      assert_released(owner)
    })
  Nil
}

fn assert_default_timeout(socket: websocket.Socket, application: Bool) -> Nil {
  let #(received, elapsed) =
    timed(fn() {
      case application {
        True -> websocket.receive_app_frame(socket)
        False -> websocket.receive_frame(socket)
      }
    })
  let assert Error(error.Timeout) = received
  let assert True = elapsed >= 75 && elapsed < 350
  Nil
}

fn receive_within(
  socket: websocket.Socket,
  wait: connection.Timeout,
  application: Bool,
) -> Result(message.Frame, error.GluegunError) {
  case application {
    True -> websocket.receive_app_frame_within(socket, wait)
    False -> websocket.receive_frame_within(socket, wait)
  }
}

fn connect(
  port: Int,
  upgrade: websocket.UpgradeOptions,
) -> Result(websocket.Socket, error.GluegunError) {
  websocket.connect(
    host: "127.0.0.1",
    port: port,
    path: "/echo",
    options: websocket.options()
      |> websocket.with_timeout(timeout(100))
      |> websocket.with_upgrade_options(upgrade),
  )
}

fn timeout(milliseconds: Int) -> connection.Timeout {
  let assert Ok(wait) = connection.milliseconds(milliseconds)
  wait
}

@external(erlang, "gluegun_ws_close_test", "with_server")
fn with_server(
  mode: String,
  callback: fn(Int) -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ws_close_test", "with_control_frames")
fn with_control_frames(
  duration: Int,
  callback: fn(Int) -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ws_close_test", "queue_control_frame")
fn queue_control_frame() -> #(connection.Connection, request.Stream)

@external(erlang, "gluegun_ws_close_test", "timed")
fn timed(callback: fn() -> a) -> #(a, Int)

@external(erlang, "gluegun_ws_close_test", "owned_connection")
fn owned_connection() -> Result(connection.Connection, error.GluegunError)

@external(erlang, "gluegun_ws_close_test", "assert_released")
fn assert_released(
  owner: connection.Connection,
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ffi_test", "current_connection")
fn current_connection() -> connection.Connection

@external(erlang, "gluegun_ffi_test", "stream_ref")
fn stream_ref() -> request.Stream

@external(erlang, "gluegun_socket_receive_control_test", "no_flow_cast")
fn no_flow_cast() -> Bool

@external(erlang, "gluegun_socket_receive_control_test", "capture_update_flow")
fn capture_update_flow() -> Result(
  #(connection.Connection, request.Stream, Int),
  Nil,
)
