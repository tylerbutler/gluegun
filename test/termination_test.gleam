import gluegun/connection
import gluegun/error
import gluegun/tls
import gluegun/websocket

pub fn falls_back_after_exactly_one_separate_stop_budget_test() -> Nil {
  let assert Ok(Nil) = with_fixture("timeout", connection.terminate)
  Nil
}

pub fn warns_on_unexpected_stop_failure_then_kills_test() -> Nil {
  let assert Ok(Nil) =
    with_fixture("failure", fn(connection) {
      let assert Ok(Nil) = connection.terminate(connection)
      connection.terminate(connection)
    })
  Nil
}

pub fn validates_guards_and_timeouts_before_cleanup_side_effects_test() -> Nil {
  let assert Ok(Nil) = guard_paths()
  Nil
}

pub fn dead_and_repeated_cleanup_drain_only_the_selected_connection_test() -> Nil {
  let assert Ok(Nil) =
    with_fixture("dead", fn(connection) {
      let assert Ok(Nil) = connection.terminate(connection)
      connection.terminate(connection)
    })
  Nil
}

pub fn target_death_disposes_a_still_blocked_stop_helper_test() -> Nil {
  let assert Ok(Nil) = with_fixture("dies", connection.terminate)
  Nil
}

pub fn caller_death_reaps_blocked_helpers_test() -> Nil {
  let assert Ok(Nil) = caller_death("nontrapping")
  Nil
}

pub fn trapping_caller_death_reaps_blocked_helpers_test() -> Nil {
  let assert Ok(Nil) = caller_death("trapping")
  Nil
}

pub fn clean_websocket_close_has_no_supervisor_killed_report_test() -> Nil {
  let assert Ok(Nil) =
    with_logs("clean", fn() {
      with_server("normal", fn(port) {
        // Adopt a retrying connection so Gun remains alive after gun_down.
        let assert Ok(retries) = connection.retry_count(5)
        let assert Ok(connection) =
          connection.options()
          |> connection.with_protocols([connection.Http1])
          |> connection.with_retry(retries)
          |> connection.open(host: "127.0.0.1", port: port)
        let assert Ok(protocol) = connection.await_up(connection, timeout(500))
        let assert Ok(stream) =
          websocket.upgrade(
            connection,
            protocol,
            "/",
            [],
            websocket.upgrade_options(),
          )
        let assert Ok(handshake) =
          websocket.await_upgrade(connection, stream, timeout(500))
        let socket =
          websocket.from_upgrade(connection, stream, handshake, timeout(500))
        let assert Ok(Nil) = websocket.close(socket)
        let assert Ok(Nil) = websocket.close(socket)
        assert_released(connection)
      })
    })
  Nil
}

pub fn failed_connect_preserves_timeout_and_releases_stalled_tls_test() -> Nil {
  let assert Ok(Nil) =
    with_stalled_tls(fn(port) {
      let #(result, elapsed) =
        timed(fn() {
          let result =
            websocket.connect(
              host: "127.0.0.1",
              port: port,
              path: "/",
              options: websocket.options()
                |> websocket.with_connect_options(
                  connection.options()
                  |> connection.with_tls_options(stalled_tls_options())
                  |> connection.with_tls_handshake_timeout(
                    connection.infinity(),
                  ),
                )
                |> websocket.with_timeout(timeout(500)),
            )
          let assert Error(error.Timeout) = result
          Ok(Nil)
        })
      let assert True = elapsed >= 450 && elapsed < 1500
      result
    })
  Nil
}

pub fn terminate_interrupts_an_infinite_tls_handshake_test() -> Nil {
  let assert Ok(Nil) =
    with_stalled_tls(fn(port) {
      let assert Ok(connection) =
        connection.options()
        |> connection.with_tls_options(stalled_tls_options())
        |> connection.with_tls_handshake_timeout(connection.infinity())
        |> connection.open(host: "127.0.0.1", port: port)
      let assert Error(error.Timeout) =
        connection.await_up(connection, timeout(500))
      let #(result, elapsed) = timed(fn() { connection.terminate(connection) })
      let assert True = elapsed < 500
      result
    })
  Nil
}

fn timeout(milliseconds: Int) -> connection.Timeout {
  let assert Ok(timeout) = connection.milliseconds(milliseconds)
  timeout
}

fn stalled_tls_options() -> tls.TlsOptions {
  // Gun 2.8 fills missing CA roots even with VerifyNone. Bypass OS trust-store
  // loading so these deadlines exercise the handshake, not local setup.
  tls.options()
  |> tls.with_verify(tls.VerifyNone)
  |> tls.with_cacerts([])
}

@external(erlang, "gluegun_terminate_test", "with_fixture")
fn with_fixture(
  mode: String,
  callback: fn(connection.Connection) -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_terminate_test", "caller_death")
fn caller_death(mode: String) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_terminate_test", "guard_paths")
fn guard_paths() -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_terminate_test", "with_logs")
fn with_logs(
  mode: String,
  callback: fn() -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_terminate_test", "with_stalled_tls")
fn with_stalled_tls(
  callback: fn(Int) -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ws_close_test", "with_server")
fn with_server(
  mode: String,
  callback: fn(Int) -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ws_close_test", "assert_released")
fn assert_released(
  connection: connection.Connection,
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ws_close_test", "timed")
fn timed(
  callback: fn() -> Result(Nil, error.GluegunError),
) -> #(Result(Nil, error.GluegunError), Int)
