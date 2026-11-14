import gleam/http
import gleam/list
import gluegun/client
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/message
import gluegun/request
import gluegun/response

type Event {
  Up(connection.Protocol)
  Down
  UnknownUp
}

pub fn sole_initial_up_is_ready_even_with_zero_timeout_test() -> Nil {
  with_mailbox([Up(connection.Http1)], fn(conn) {
    let assert Ok(connection.Http1) = connection.await_up(conn, timeout(0))
    Nil
  })
}

pub fn queued_up_then_down_is_not_ready_test() -> Nil {
  with_mailbox([Up(connection.Http1), Down], fn(conn) {
    let assert Error(error.Timeout) = connection.await_up(conn, timeout(0))
    Nil
  })
}

pub fn newest_queued_up_wins_even_with_zero_timeout_test() -> Nil {
  with_mailbox([Up(connection.Http1), Down, Up(connection.Http2)], fn(conn) {
    let assert Ok(connection.Http2) = connection.await_up(conn, timeout(0))
    Nil
  })
}

pub fn multiple_queued_cycles_ending_down_are_not_ready_test() -> Nil {
  with_mailbox(
    [Down, Up(connection.Http2), Down, Up(connection.Http1), Down],
    fn(conn) {
      let assert Error(error.Timeout) = connection.await_up(conn, timeout(0))
      Nil
    },
  )
}

pub fn unknown_latest_protocol_retains_typed_decode_error_test() -> Nil {
  with_mailbox([Up(connection.Http1), Down, UnknownUp], fn(conn) {
    let assert Error(error.DecodeError("Invalid protocol")) =
      connection.await_up(conn, timeout(0))
    Nil
  })
}

pub fn lifecycle_drain_returns_nil_and_preserves_other_mail_test() -> Nil {
  with_mailbox([Up(connection.Http1), Down, Up(connection.Http2)], fn(conn) {
    assert drain_lifecycle(conn) == Nil
    Nil
  })
}

pub fn waiting_through_down_events_keeps_one_finite_budget_test() -> Nil {
  with_down_timers(fn(conn) {
    let #(result, elapsed) = timed_await(conn, timeout(80))
    let assert Error(error.Timeout) = result
    let assert True = elapsed >= 60
    let assert True = elapsed < 180
    Nil
  })
}

pub fn wait_through_queued_and_future_down_until_new_up_test() -> Nil {
  with_reconnecting_mailbox(fn(conn) {
    let assert Ok(connection.Http2) = connection.await_up(conn, timeout(500))
    Nil
  })
}

pub fn infinite_wait_can_reconnect_after_down_test() -> Nil {
  with_reconnecting_mailbox(fn(conn) {
    let assert Ok(connection.Http2) =
      connection.await_up(conn, connection.infinity())
    Nil
  })
}

pub fn readiness_process_exit_preserves_external_down_monitor_test() -> Nil {
  with_dead_connection(fn(conn) {
    let assert Error(error.ConnectionDown(_)) =
      connection.await_up(conn, timeout(500))
    assert drain_lifecycle(conn) == Nil
    Nil
  })
}

pub fn common_client_drains_before_dispatch_and_after_success_test() -> Nil {
  common_client(False, False)
}

pub fn common_client_drains_after_dispatch_failure_test() -> Nil {
  common_client(True, False)
}

pub fn common_client_drains_after_collection_failure_cleanup_test() -> Nil {
  common_client(False, True)
}

fn common_client(dispatch_failure: Bool, collection_failure: Bool) -> Nil {
  with_mailbox([Up(connection.Http1), Down], fn(conn) {
    let outcome =
      client.request_with(
        conn,
        http.Get,
        "/",
        [],
        <<>>,
        request.options(),
        timeout(500),
        fn(conn, _, _, _, _, _) {
          let assert 0 = lifecycle_count(conn)
          enqueue(conn, [Down, Up(connection.Http1)])
          case dispatch_failure {
            True -> Error(error.InvalidOptions("dispatch"))
            False -> Ok(new_stream())
          }
        },
        fn(conn, _, _) {
          enqueue(conn, [Up(connection.Http1), Down])
          case collection_failure {
            True -> Error(error.StreamError("collection"))
            False -> Ok(message.Response(fin.Fin, 204, []))
          }
        },
      )
    case dispatch_failure, collection_failure {
      True, _ -> {
        let assert Error(error.InvalidOptions("dispatch")) = outcome
        Nil
      }
      False, True -> {
        let assert Error(error.StreamError("collection")) = outcome
        Nil
      }
      False, False -> {
        let assert Ok(response) = outcome
        let assert 204 = response.response.status
        Nil
      }
    }
  })
}

pub fn real_retry_stale_up_does_not_report_disconnected_ready_test() -> Nil {
  with_retry_peer(fn(conn, peer) {
    let assert Ok(Nil) = wait_lifecycle(conn, 1)
    let assert Ok(Nil) = close_peer(peer)
    let assert Ok(Nil) = wait_lifecycle(conn, 2)
    let assert Error(error.Timeout) = connection.await_up(conn, timeout(0))
    let assert Ok(connection.Http1) = connection.await_up(conn, timeout(1500))
    let assert 0 = lifecycle_count(conn)
    Nil
  })
}

pub fn real_retry_down_wait_obeys_finite_timeout_test() -> Nil {
  with_retry_peer(fn(conn, peer) {
    let assert Ok(connection.Http1) = connection.await_up(conn, timeout(1500))
    let assert Ok(Nil) = close_peer(peer)
    let assert Ok(Nil) = wait_lifecycle(conn, 1)
    let #(result, elapsed) = timed_await(conn, timeout(50))
    let assert Error(error.Timeout) = result
    let assert True = elapsed >= 40
    let assert True = elapsed < 180
    let assert Ok(connection.Http1) = connection.await_up(conn, timeout(1500))
    Nil
  })
}

pub fn real_retry_latest_queued_up_succeeds_with_zero_poll_test() -> Nil {
  with_retry_peer(fn(conn, peer) {
    let assert Ok(Nil) = wait_lifecycle(conn, 1)
    let assert Ok(Nil) = close_peer(peer)
    let assert Ok(Nil) = wait_lifecycle(conn, 3)
    let assert Ok(connection.Http1) = connection.await_up(conn, timeout(0))
    let assert 0 = lifecycle_count(conn)
    Nil
  })
}

pub fn real_repeated_retry_cycles_high_level_client_drains_mailbox_test() -> Nil {
  with_retry_peer(fn(conn, peer) {
    let assert Ok(connection.Http1) = connection.await_up(conn, timeout(1500))
    list.each([1, 2, 3], fn(_) {
      let assert Ok(Nil) = close_peer(peer)
      let assert Ok(Nil) = wait_lifecycle(conn, 2)
      let assert Ok(response) = client.get(conn, "/", [], timeout(1500))
      let assert 200 = response.response.status
      let assert <<"ok":utf8>> = response.response.body
      let assert 0 = lifecycle_count(conn)
      Nil
    })
  })
}

pub fn real_retry_client_failure_drains_after_cleanup_and_can_reconnect_test() -> Nil {
  with_retry_peer(fn(conn, peer) {
    let assert Ok(connection.Http1) = connection.await_up(conn, timeout(1500))
    let assert Ok(Nil) = fail_peer(peer)
    let assert Error(error.StreamError(_)) =
      retry_client_failure(conn, timeout(1500))
    let assert 0 = lifecycle_count(conn)
    let assert Ok(connection.Http1) = connection.await_up(conn, timeout(1500))
    let assert Ok(response) = client.get(conn, "/", [], timeout(1500))
    let assert <<"ok":utf8>> = response.response.body
    let assert 0 = lifecycle_count(conn)
    Nil
  })
}

fn timeout(value: Int) -> connection.Timeout {
  let assert Ok(timeout) = connection.milliseconds(value)
  timeout
}

type Peer

@external(erlang, "gluegun_lifecycle_test", "with_mailbox")
fn with_mailbox(
  events: List(Event),
  callback: fn(connection.Connection) -> Nil,
) -> Nil

@external(erlang, "gluegun_lifecycle_test", "enqueue")
fn enqueue(connection: connection.Connection, events: List(Event)) -> Nil

@external(erlang, "gluegun_ffi_test", "stream_ref")
fn new_stream() -> request.Stream

@external(erlang, "gluegun_ffi", "drain_lifecycle")
fn drain_lifecycle(connection: connection.Connection) -> Nil

@external(erlang, "gluegun_lifecycle_test", "with_down_timers")
fn with_down_timers(callback: fn(connection.Connection) -> Nil) -> Nil

@external(erlang, "gluegun_lifecycle_test", "with_reconnecting_mailbox")
fn with_reconnecting_mailbox(callback: fn(connection.Connection) -> Nil) -> Nil

@external(erlang, "gluegun_lifecycle_test", "with_dead_connection")
fn with_dead_connection(callback: fn(connection.Connection) -> Nil) -> Nil

@external(erlang, "gluegun_lifecycle_test", "timed_await")
fn timed_await(
  connection: connection.Connection,
  timeout: connection.Timeout,
) -> #(Result(connection.Protocol, error.GluegunError), Int)

@external(erlang, "gluegun_lifecycle_test", "with_retry_peer")
fn with_retry_peer(callback: fn(connection.Connection, Peer) -> Nil) -> Nil

@external(erlang, "gluegun_lifecycle_test", "close_peer")
fn close_peer(peer: Peer) -> Result(Nil, String)

@external(erlang, "gluegun_lifecycle_test", "fail_peer")
fn fail_peer(peer: Peer) -> Result(Nil, String)

@external(erlang, "gluegun_lifecycle_test", "retry_client_failure")
fn retry_client_failure(
  connection: connection.Connection,
  timeout: connection.Timeout,
) -> Result(response.Response(BitArray), error.GluegunError)

@external(erlang, "gluegun_lifecycle_test", "wait_lifecycle")
fn wait_lifecycle(
  connection: connection.Connection,
  count: Int,
) -> Result(Nil, String)

@external(erlang, "gluegun_lifecycle_test", "lifecycle_count")
fn lifecycle_count(connection: connection.Connection) -> Int
