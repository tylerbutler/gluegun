import gleam/list
import gleam/option.{None, Some}
import gluegun/connection
import gluegun/error
import gluegun/message
import gluegun/request
import gluegun/tls
import gluegun/websocket

pub fn validates_the_entire_subprotocol_list_before_cast_test() -> Nil {
  list.each(
    [
      "",
      "bad\r\nInjected: yes",
      "bad token",
      "bad,token",
      "bad;token",
      "é",
      "bad\u{0000}",
      "bad\u{007F}",
    ],
    fn(invalid) {
      let assert Error(error.InvalidOptions(_)) =
        websocket.upgrade(
          current_connection(),
          connection.Http1,
          "/ws",
          [],
          websocket.upgrade_options()
            |> websocket.with_subprotocols(["valid", invalid, "also-valid"]),
        )
      let assert True = no_cast()
    },
  )
}

pub fn retains_selected_subprotocol_and_response_headers_on_socket_test() -> Nil {
  subprotocol_scenario("subprotocols", ["chat", "superchat"], "superchat")
}

pub fn validates_all_tokens_before_converting_internal_callback_modules_test() -> Nil {
  let assert Error(error.InvalidOptions("Ws(InvalidSubprotocol)")) =
    websocket.upgrade(
      current_connection(),
      connection.Http1,
      "/",
      [],
      websocket.upgrade_options()
        |> websocket.with_protocol_module(
          "valid",
          "nonexistent_gluegun_handler",
        )
        |> websocket.with_protocol_module(
          "invalid token",
          "another_nonexistent_handler",
        ),
    )
  let assert True = no_cast()
  Nil
}

pub fn keeps_outbound_validation_and_runtime_failures_distinct_test() -> Nil {
  let valid = websocket.socket(current_connection(), stream_ref(), timeout(500))
  let assert Error(error.InvalidMessage(_)) =
    websocket.send_frame(valid, message.Ping(<<0:size(1008)>>))
  let invalid =
    websocket.socket(invalid_connection(), stream_ref(), timeout(500))
  let assert Error(error.ErlangError(_)) =
    websocket.send_frame(invalid, message.Text("valid payload"))
  let assert Error(error.ErlangError(_)) = websocket.receive_frame(invalid)
  let assert True = no_cast()
  Nil
}

pub fn offers_one_subprotocol_on_the_wire_test() -> Nil {
  subprotocol_scenario("single_protocol", ["chat"], "chat")
}

fn subprotocol_scenario(
  mode: String,
  offered: List(String),
  selected: String,
) -> Nil {
  let assert Ok(Nil) =
    with_server(mode, fn(port) {
      let assert Ok(socket) =
        connect(
          port,
          websocket.upgrade_options() |> websocket.with_subprotocols(offered),
        )
      let assert Some(actual) = websocket.selected_subprotocol(socket)
      let assert True = actual == selected
      let handshake = websocket.handshake(socket)
      let assert Some(actual) = websocket.handshake_subprotocol(handshake)
      let assert True = actual == selected
      let assert True =
        list.contains(websocket.handshake_headers(handshake), #(
          "sec-websocket-protocol",
          selected,
        ))
      websocket.close(socket)
    })
  Nil
}

pub fn skips_100_and_103_before_upgrade_under_one_deadline_test() -> Nil {
  let assert Ok(Nil) =
    with_server("inform", fn(port) {
      let assert Ok(socket) = connect(port, websocket.upgrade_options())
      let assert None = websocket.selected_subprotocol(socket)
      let assert Ok(Nil) = websocket.send_text(socket, "after upgrade")
      let assert Ok(message.Text("after upgrade")) =
        websocket.receive_frame(socket)
      websocket.close(socket)
    })
  Nil
}

pub fn unlimited_upgrade_budget_accepts_informational_responses_test() -> Nil {
  let assert Ok(Nil) =
    with_server("inform", fn(port) {
      let assert Ok(socket) =
        websocket.connect(
          host: "127.0.0.1",
          port: port,
          path: "/",
          options: websocket.options()
            |> websocket.with_timeout(connection.infinity()),
        )
      websocket.close(socket)
    })
  Nil
}

pub fn dedicated_receive_preserves_other_connections_streams_and_application_mail_test() -> Nil {
  with_ws_mailbox(fn(connection, stream) {
    let socket = websocket.socket(connection, stream, timeout(500))
    let assert Ok(message.Text("selected")) = websocket.receive_frame(socket)
    let assert Error(error.ConnectionDown(_)) = websocket.receive_frame(socket)
    Nil
  })
}

pub fn informational_responses_do_not_reset_the_upgrade_deadline_test() -> Nil {
  let assert Ok(Nil) =
    with_server("deadline", fn(port) {
      let assert Ok(connection) = open(port, 0)
      let assert Ok(stream) =
        websocket.upgrade(
          connection,
          connection.Http1,
          "/",
          [],
          websocket.upgrade_options(),
        )
      let #(result, elapsed) = timed_upgrade(connection, stream, timeout(50))
      let cleanup = connection.terminate(connection)
      let assert Error(error.Timeout) = result
      let assert True = elapsed >= 35 && elapsed < 200
      cleanup
    })
  Nil
}

pub fn zero_upgrade_budget_does_not_consume_a_queued_upgrade_test() -> Nil {
  let #(connection, stream, raw) = incoming_upgrade()
  let assert Error(error.Timeout) =
    websocket.await_upgrade(connection, stream, timeout(0))
  let assert Ok(_) = message.decode(raw)
  let assert Ok(message.Upgrade(_, _)) =
    message.await(connection, stream, timeout(500))
  Nil
}

pub fn connect_forces_http1_and_zero_retry_after_caller_options_test() -> Nil {
  let assert Ok(retries) = connection.retry_count(7)
  let options =
    websocket.options()
    |> websocket.with_connect_options(
      connection.options()
      |> connection.with_protocols([connection.Http2, connection.Http1])
      |> connection.with_retry(retries),
    )
    |> websocket.connect_options
  let assert Some([connection.Http1]) = connection.protocols(options)
  let assert Ok(zero) = connection.retry_count(0)
  let assert True = connection.retry(options) == zero
  Nil
}

pub fn default_socket_detects_a_dropped_connection_test() -> Nil {
  let assert Ok(Nil) =
    with_server("drop", fn(port) {
      let assert Ok(socket) = connect(port, websocket.upgrade_options())
      let result = websocket.receive_frame(socket)
      let cleanup = websocket.close(socket)
      let assert Error(error.ConnectionDown(_)) = result
      cleanup
    })
  Nil
}

pub fn tls_connect_forces_http1_alpn_after_caller_protocol_options_test() -> Nil {
  let assert Ok(Nil) =
    with_tls_server(fn(port, cas) {
      tls_connect(port, tls.options() |> tls.with_cacerts(cas))
    })
  Nil
}

pub fn explicitly_insecure_tls_still_permits_disabled_sni_test() -> Nil {
  let assert Ok(Nil) =
    with_tls_server(fn(port, _) {
      tls_connect(
        port,
        tls.options()
          |> tls.with_verify(tls.VerifyNone)
          |> tls.with_server_name_indication(tls.Disable),
      )
    })
  Nil
}

fn tls_connect(
  port: Int,
  tls_options: tls.TlsOptions,
) -> Result(Nil, error.GluegunError) {
  let assert Ok(retries) = connection.retry_count(5)
  let supplied =
    connection.options()
    |> connection.with_address_family(connection.Ipv4)
    |> connection.with_protocols([connection.Http2, connection.Http1])
    |> connection.with_retry(retries)
    |> connection.with_tls_options(tls_options)
  let assert Ok(socket) =
    websocket.connect(
      host: "localhost",
      port: port,
      path: "/",
      options: websocket.options()
        |> websocket.with_connect_options(supplied)
        |> websocket.with_timeout(timeout(1000)),
    )
  websocket.close(socket)
}

pub fn adopted_retrying_socket_detects_a_dropped_connection_test() -> Nil {
  let assert Ok(Nil) =
    with_server("drop", fn(port) {
      let assert Ok(connection) = open(port, 5)
      let assert Ok(stream) =
        websocket.upgrade(
          connection,
          connection.Http1,
          "/",
          [],
          websocket.upgrade_options(),
        )
      let assert Ok(handshake) =
        websocket.await_upgrade(connection, stream, timeout(500))
      let socket =
        websocket.from_upgrade(connection, stream, handshake, timeout(500))
      let result = websocket.receive_frame(socket)
      let cleanup = connection.terminate(connection)
      let assert Error(error.ConnectionDown(_)) = result
      cleanup
    })
  Nil
}

pub fn close_restores_consumed_flow_one_test() -> Nil {
  flow_scenario("flow_consumed", True)
}

pub fn close_restores_negative_credit_from_coalesced_frames_test() -> Nil {
  flow_scenario("flow_coalesced", True)
}

pub fn close_drains_queued_coalesced_frames_with_flow_one_test() -> Nil {
  flow_scenario("flow_coalesced", False)
}

pub fn close_replenishes_nonclose_frames_arriving_during_teardown_test() -> Nil {
  flow_scenario("flow_during", False)
}

fn flow_scenario(mode: String, consume: Bool) -> Nil {
  let assert Ok(Nil) =
    with_server(mode, fn(port) {
      let assert Ok(upgrade) =
        websocket.upgrade_options() |> websocket.with_flow(1)
      let assert Ok(socket) = connect(port, upgrade)
      case consume {
        True -> {
          let assert Ok(message.Text("one")) = websocket.receive_frame(socket)
          Nil
        }

        False -> Nil
      }
      let assert Ok(connection) = owned_connection()
      let result = websocket.close(socket)
      let released = assert_released(connection)
      let assert Ok(Nil) = result
      let assert Ok(Nil) = websocket.close(socket)
      released
    })
  Nil
}

pub fn flow_builder_rejects_nonpositive_credit_test() -> Nil {
  list.each([0, -1], fn(credit) {
    let assert Error(error.InvalidOptions(_)) =
      websocket.upgrade_options() |> websocket.with_flow(credit)
  })
}

fn open(
  port: Int,
  retries: Int,
) -> Result(connection.Connection, error.GluegunError) {
  let assert Ok(retries) = connection.retry_count(retries)
  let assert Ok(connection) =
    connection.options()
    |> connection.with_protocols([connection.Http1])
    |> connection.with_retry(retries)
    |> connection.open(host: "127.0.0.1", port: port)
  let assert Ok(connection.Http1) =
    connection.await_up(connection, timeout(500))
  Ok(connection)
}

fn connect(
  port: Int,
  upgrade: websocket.UpgradeOptions,
) -> Result(websocket.Socket, error.GluegunError) {
  websocket.connect(
    host: "127.0.0.1",
    port: port,
    path: "/",
    options: websocket.options()
      |> websocket.with_timeout(timeout(500))
      |> websocket.with_upgrade_options(upgrade),
  )
}

fn timeout(milliseconds: Int) -> connection.Timeout {
  let assert Ok(timeout) = connection.milliseconds(milliseconds)
  timeout
}

fn incoming_upgrade() -> #(
  connection.Connection,
  request.Stream,
  message.GunMessage,
) {
  incoming("upgrade", "valid")
}

@external(erlang, "gluegun_ffi_test", "current_connection")
fn current_connection() -> connection.Connection

@external(erlang, "gluegun_ffi_test", "invalid_connection")
fn invalid_connection() -> connection.Connection

@external(erlang, "gluegun_ffi_test", "stream_ref")
fn stream_ref() -> request.Stream

@external(erlang, "gluegun_runtime_regression_test", "no_cast")
fn no_cast() -> Bool

@external(erlang, "gluegun_runtime_regression_test", "incoming")
fn incoming(
  kind: String,
  fault: String,
) -> #(connection.Connection, request.Stream, message.GunMessage)

@external(erlang, "gluegun_ws_close_test", "with_server")
fn with_server(
  mode: String,
  callback: fn(Int) -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ws_close_test", "with_tls_server")
fn with_tls_server(
  callback: fn(Int, List(BitArray)) -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_runtime_regression_test", "with_ws_mailbox")
fn with_ws_mailbox(
  callback: fn(connection.Connection, request.Stream) -> Nil,
) -> Nil

@external(erlang, "gluegun_ws_close_test", "owned_connection")
fn owned_connection() -> Result(connection.Connection, error.GluegunError)

@external(erlang, "gluegun_ws_close_test", "assert_released")
fn assert_released(
  connection: connection.Connection,
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_runtime_regression_test", "timed_upgrade")
fn timed_upgrade(
  connection: connection.Connection,
  stream: request.Stream,
  timeout: connection.Timeout,
) -> #(Result(websocket.Handshake, error.GluegunError), Int)
