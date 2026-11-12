import gluegun/connection
import gluegun/error
import gluegun/message
import gluegun/websocket

pub fn tears_down_before_reraising_a_gleam_panic_test() -> Nil {
  let assert Ok(Nil) =
    assert_scoped_exception("normal", fn() {
      panic as "scoped WebSocket callback panic"
    })
  Nil
}

pub fn preserves_a_failed_assertion_after_cleanup_timeout_test() -> Nil {
  let assert Ok(Nil) =
    assert_scoped_exception("stall", fn() {
      let assert Ok(_) = connection.milliseconds(-1)
      Ok(Nil)
    })
  Nil
}

@external(erlang, "gluegun_ws_close_test", "assert_scoped_exception")
fn assert_scoped_exception(
  mode: String,
  failure_callback: fn() -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

pub fn preserves_erlang_error_after_teardown_test() -> Nil {
  let assert Ok(Nil) = assert_exception_cleanup("normal", "error")
  Nil
}

pub fn preserves_erlang_exit_after_teardown_test() -> Nil {
  let assert Ok(Nil) = assert_exception_cleanup("normal", "exit")
  Nil
}

pub fn preserves_erlang_throw_after_teardown_test() -> Nil {
  let assert Ok(Nil) = assert_exception_cleanup("normal", "throw")
  Nil
}

pub fn preserves_erlang_error_after_cleanup_timeout_test() -> Nil {
  let assert Ok(Nil) = assert_exception_cleanup("stall", "error")
  Nil
}

pub fn preserves_erlang_exit_after_cleanup_timeout_test() -> Nil {
  let assert Ok(Nil) = assert_exception_cleanup("stall", "exit")
  Nil
}

pub fn preserves_erlang_throw_after_cleanup_timeout_test() -> Nil {
  let assert Ok(Nil) = assert_exception_cleanup("stall", "throw")
  Nil
}

pub fn cleanup_cannot_replace_the_original_callback_exception_test() -> Nil {
  let assert Ok(Nil) = cleanup_guard_paths()
  Nil
}

@external(erlang, "gluegun_ws_close_test", "assert_exception_cleanup")
fn assert_exception_cleanup(
  mode: String,
  class: String,
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ws_close_test", "cleanup_guard_paths")
fn cleanup_guard_paths() -> Result(Nil, error.GluegunError)

pub fn keeps_errors_typed_and_accepts_an_already_exited_process_test() -> Nil {
  let actual_1 = error_paths()
  let expected_1 = Ok(Nil)
  let assert #(True, _, _) = #(actual_1 == expected_1, actual_1, expected_1)
  Nil
}

pub fn exchanges_and_releases_using_public_socket_apis_test() -> Nil {
  let actual_2 =
    with_server("normal", fn(port) {
      let assert Ok(socket) = connect(port, options(500))
      let assert Ok(connection) = owned_connection()
      let actual_3 = websocket.send_text(socket, "hello")
      let expected_3 = Ok(Nil)
      let assert #(True, _, _) = #(actual_3 == expected_3, actual_3, expected_3)
      let actual_4 = websocket.receive_app_frame(socket)
      let expected_4 = Ok(message.Text("hello"))
      let assert #(True, _, _) = #(actual_4 == expected_4, actual_4, expected_4)
      let actual_5 = websocket.close(socket)
      let expected_5 = Ok(Nil)
      let assert #(True, _, _) = #(actual_5 == expected_5, actual_5, expected_5)
      let actual_6 = websocket.close(socket)
      let expected_6 = Ok(Nil)
      let assert #(True, _, _) = #(actual_6 == expected_6, actual_6, expected_6)
      assert_released(connection)
    })
  let expected_2 = Ok(Nil)
  let assert #(True, _, _) = #(actual_2 == expected_2, actual_2, expected_2)
  Nil
}

pub fn keeps_send_close_frame_separate_from_teardown_test() -> Nil {
  let actual_7 =
    with_server("stall", fn(port) {
      let assert Ok(socket) = connect(port, options(50))
      let assert Ok(connection) = owned_connection()
      let actual_8 = websocket.send_close_frame(socket)
      let expected_8 = Ok(Nil)
      let assert #(True, _, _) = #(actual_8 == expected_8, actual_8, expected_8)
      // A live connection remains discoverable after the frame-only call.
      let actual_9 = owned_connection()
      let expected_9 = Ok(connection)
      let assert #(True, _, _) = #(actual_9 == expected_9, actual_9, expected_9)
      let actual_10 = websocket.close(socket)
      let expected_10 = Error(error.Timeout)
      let assert #(True, _, _) = #(
        actual_10 == expected_10,
        actual_10,
        expected_10,
      )
      assert_released(connection)
    })
  let expected_7 = Ok(Nil)
  let assert #(True, _, _) = #(actual_7 == expected_7, actual_7, expected_7)
  Nil
}

pub fn handles_a_peer_close_already_received_by_the_caller_test() -> Nil {
  let actual_11 =
    with_server("peer_close", fn(port) {
      let assert Ok(socket) = connect(port, options(500))
      let assert Ok(connection) = owned_connection()
      let actual_12 = websocket.receive_frame(socket)
      let expected_12 = Ok(message.Close)
      let assert #(True, _, _) = #(
        actual_12 == expected_12,
        actual_12,
        expected_12,
      )
      let actual_13 = websocket.close(socket)
      let expected_13 = Ok(Nil)
      let assert #(True, _, _) = #(
        actual_13 == expected_13,
        actual_13,
        expected_13,
      )
      assert_released(connection)
    })
  let expected_11 = Ok(Nil)
  let assert #(True, _, _) = #(actual_11 == expected_11, actual_11, expected_11)
  Nil
}

pub fn reports_peer_failure_and_still_releases_the_process_test() -> Nil {
  let actual_14 =
    with_server("failure", fn(port) {
      let assert Ok(socket) = connect(port, options(500))
      let assert Ok(connection) = owned_connection()
      case websocket.close(socket) {
        Error(error.ConnectionDown(_)) -> Nil
        other -> {
          let actual_15 = other
          let expected_15 = Error(error.ConnectionDown("closed"))
          let assert #(True, _, _) = #(
            actual_15 == expected_15,
            actual_15,
            expected_15,
          )
          Nil
        }
      }
      assert_released(connection)
    })
  let expected_14 = Ok(Nil)
  let assert #(True, _, _) = #(actual_14 == expected_14, actual_14, expected_14)
  Nil
}

pub fn remembers_a_received_peer_close_with_a_reason_test() -> Nil {
  let actual_16 =
    with_server("peer_reason", fn(port) {
      let assert Ok(socket) = connect(port, options(500))
      let assert Ok(connection) = owned_connection()
      let actual_17 = websocket.receive_app_frame(socket)
      let expected_17 = Ok(message.CloseWithReason(1000, <<"bye":utf8>>))
      let assert #(True, _, _) = #(
        actual_17 == expected_17,
        actual_17,
        expected_17,
      )
      let actual_18 = websocket.close(socket)
      let expected_18 = Ok(Nil)
      let assert #(True, _, _) = #(
        actual_18 == expected_18,
        actual_18,
        expected_18,
      )
      assert_released(connection)
    })
  let expected_16 = Ok(Nil)
  let assert #(True, _, _) = #(actual_16 == expected_16, actual_16, expected_16)
  Nil
}

pub fn bounds_an_unresponsive_peer_test() -> Nil {
  timeout_scenario("stall", options(50), 30, 500)
  Nil
}

pub fn does_not_extend_the_deadline_for_incoming_frames_test() -> Nil {
  timeout_scenario("chatter", options(50), 30, 500)
  Nil
}

pub fn supports_a_zero_close_deadline_test() -> Nil {
  timeout_scenario("stall", options(0), 0, 500)
  Nil
}

pub fn bounds_cleanup_even_with_an_infinite_receive_timeout_test() -> Nil {
  timeout_scenario(
    "stall",
    websocket.options() |> websocket.with_timeout(connection.infinity()),
    4900,
    6500,
  )
  Nil
}

pub fn does_not_mistake_gun_s_closing_timeout_for_a_peer_reply_test() -> Nil {
  let upgrade =
    websocket.upgrade_options()
    |> websocket.with_closing_timeout(timeout(20))
  timeout_scenario(
    "stall",
    options(500) |> websocket.with_upgrade_options(upgrade),
    0,
    500,
  )
  Nil
}

pub fn preserves_callback_errors_after_cleanup_timeout_test() -> Nil {
  let actual_19 =
    with_server("stall", fn(port) {
      let assert Ok(connection) = {
        let actual_20 =
          websocket.with_socket(
            host: "127.0.0.1",
            port: port,
            path: "/echo",
            options: options(50),
            callback: fn(_) {
              let assert Ok(connection) = owned_connection()
              remember_connection(connection)
              Error(error.InvalidMessage("callback failed"))
            },
          )
        let expected_20 = Error(error.InvalidMessage("callback failed"))
        let assert #(True, _, _) = #(
          actual_20 == expected_20,
          actual_20,
          expected_20,
        )
        remembered_connection()
      }
      assert_released(connection)
    })
  let expected_19 = Ok(Nil)
  let assert #(True, _, _) = #(actual_19 == expected_19, actual_19, expected_19)
  Nil
}

pub fn allows_a_callback_to_close_its_own_socket_test() -> Nil {
  let actual_21 =
    with_server("normal", fn(port) {
      websocket.with_socket(
        host: "127.0.0.1",
        port: port,
        path: "/echo",
        options: options(500),
        callback: fn(socket) { websocket.close(socket) },
      )
    })
  let expected_21 = Ok(Nil)
  let assert #(True, _, _) = #(actual_21 == expected_21, actual_21, expected_21)
  Nil
}

pub fn returns_a_cleanup_error_after_callback_success_test() -> Nil {
  let actual_22 =
    with_server("stall", fn(port) {
      let result =
        websocket.with_socket(
          host: "127.0.0.1",
          port: port,
          path: "/echo",
          options: options(50),
          callback: fn(_) {
            let assert Ok(connection) = owned_connection()
            remember_connection(connection)
            Ok(Nil)
          },
        )
      let actual_23 = result
      let expected_23 = Error(error.Timeout)
      let assert #(True, _, _) = #(
        actual_23 == expected_23,
        actual_23,
        expected_23,
      )
      let assert Ok(connection) = remembered_connection()
      assert_released(connection)
    })
  let expected_22 = Ok(Nil)
  let assert #(True, _, _) = #(actual_22 == expected_22, actual_22, expected_22)
  Nil
}

fn timeout_scenario(
  name: String,
  options: websocket.Options,
  minimum: Int,
  maximum: Int,
) -> Nil {
  let actual_24 =
    with_server(name, fn(port) {
      // Upgrade must complete before a short or zero receive timeout is used.
      let assert Ok(socket) = case
        websocket.options_timeout(options) == timeout(0)
      {
        True -> connect_zero_timeout(port)
        False -> connect(port, options)
      }
      let assert Ok(connection) = owned_connection()
      let #(result, elapsed) = timed(fn() { websocket.close(socket) })
      let actual_25 = result
      let expected_25 = Error(error.Timeout)
      let assert #(True, _, _) = #(
        actual_25 == expected_25,
        actual_25,
        expected_25,
      )
      let actual_26 = {
        elapsed >= minimum && elapsed < maximum
      }
      let expected_26 = True
      let assert #(True, _, _) = #(
        actual_26 == expected_26,
        actual_26,
        expected_26,
      )
      assert_released(connection)
    })
  let expected_24 = Ok(Nil)
  let assert #(True, _, _) = #(actual_24 == expected_24, actual_24, expected_24)
  Nil
}

fn connect(
  port: Int,
  options: websocket.Options,
) -> Result(websocket.Socket, error.GluegunError) {
  websocket.connect(
    host: "127.0.0.1",
    port: port,
    path: "/echo",
    options: options,
  )
}

fn connect_zero_timeout(
  port: Int,
) -> Result(websocket.Socket, error.GluegunError) {
  let assert Ok(connection) =
    connection.options()
    |> connection.with_transport(connection.Tcp)
    |> connection.with_protocols([connection.Http1])
    |> connection.open(host: "127.0.0.1", port: port)
  let assert Ok(protocol) = connection.await_up(connection, timeout(500))
  let assert Ok(stream) =
    websocket.upgrade(
      connection,
      protocol,
      "/echo",
      [],
      websocket.upgrade_options(),
    )
  let assert Ok(handshake) =
    websocket.await_upgrade(connection, stream, timeout(500))
  Ok(websocket.from_upgrade(connection, stream, handshake, timeout(0)))
}

fn options(milliseconds: Int) -> websocket.Options {
  websocket.options() |> websocket.with_timeout(timeout(milliseconds))
}

fn timeout(milliseconds: Int) -> connection.Timeout {
  let assert Ok(timeout) = connection.milliseconds(milliseconds)
  timeout
}

@external(erlang, "gluegun_ws_close_test", "with_server")
fn with_server(
  name: String,
  callback: fn(Int) -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ws_close_test", "owned_connection")
fn owned_connection() -> Result(connection.Connection, error.GluegunError)

@external(erlang, "gluegun_ws_close_test", "assert_released")
fn assert_released(
  connection: connection.Connection,
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ws_close_test", "timed")
fn timed(
  callback: fn() -> Result(Nil, error.GluegunError),
) -> #(Result(Nil, error.GluegunError), Int)

@external(erlang, "gluegun_ws_close_test", "remember_connection")
fn remember_connection(connection: connection.Connection) -> Nil

@external(erlang, "gluegun_ws_close_test", "remembered_connection")
fn remembered_connection() -> Result(connection.Connection, error.GluegunError)

@external(erlang, "gluegun_ws_close_test", "error_paths")
fn error_paths() -> Result(Nil, error.GluegunError)
