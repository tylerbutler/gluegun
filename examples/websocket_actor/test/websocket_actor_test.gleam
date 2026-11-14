import gleam/erlang/process
import gluegun/error
import gluegun/message
import gluegun/websocket
import unitest
import websocket_actor

pub fn main() -> Nil {
  unitest.main()
}

pub fn receives_frames_and_application_commands_in_the_owner_actor_test() -> Nil {
  let assert Ok(Nil) =
    with_server("normal", fn(port) {
      let notices = process.new_subject()
      let assert Ok(started) =
        websocket_actor.start("127.0.0.1", port, "/echo", options(), notices)
      let assert Ok(Nil) = assert_owner(started.pid)
      let monitor = process.monitor(started.pid)
      let _ = process.call(started.data, 1000, websocket_actor.Inspect)
      let assert Ok(Nil) =
        process.call(started.data, 1000, websocket_actor.SendText("hello", _))
      let assert Ok(websocket_actor.FrameReceived(message.Text("hello"))) =
        process.receive(notices, 1000)
      let _ = process.call(started.data, 1000, websocket_actor.Inspect)
      let assert Ok(Nil) =
        process.call(started.data, 1000, websocket_actor.Close)
      await_exit(monitor)
      Ok(Nil)
    })
  Nil
}

pub fn restores_actor_delivered_coalesced_finite_credit_before_close_test() -> Nil {
  let assert Ok(Nil) =
    with_server("flow_coalesced", fn(port) {
      let notices = process.new_subject()
      let assert Ok(upgrade) =
        websocket.upgrade_options() |> websocket.with_flow(1)
      let assert Ok(started) =
        websocket_actor.start("127.0.0.1", port, "/echo", upgrade, notices)
      let monitor = process.monitor(started.pid)
      let assert Ok(websocket_actor.FrameReceived(message.Text("one"))) =
        process.receive(notices, 1000)
      let assert Ok(websocket_actor.FrameReceived(message.Text("two"))) =
        process.receive(notices, 1000)
      let assert Ok(websocket_actor.FrameReceived(message.Text("three"))) =
        process.receive(notices, 1000)
      let _ = process.call(started.data, 1000, websocket_actor.Inspect)
      let assert Ok(Nil) =
        process.call(started.data, 1000, websocket_actor.Close)
      await_exit(monitor)
      Ok(Nil)
    })
  Nil
}

pub fn reports_a_real_websocket_disconnect_as_a_lifecycle_event_test() -> Nil {
  let assert Ok(Nil) =
    with_server("drop", fn(port) {
      let notices = process.new_subject()
      let assert Ok(started) =
        websocket_actor.start("127.0.0.1", port, "/echo", options(), notices)
      process.sleep(100)
      let monitor = process.monitor(started.pid)
      release_disconnect()
      let assert Ok(websocket_actor.Lifecycle(message.ConnectionDown(
        _,
        message.WebSocketProtocol,
        error.ConnectionDown(_),
        _,
      ))) = process.receive(notices, 1000)
      await_exit(monitor)
      Ok(Nil)
    })
  Nil
}

pub fn stops_when_the_owned_gun_process_exits_without_a_gun_down_test() -> Nil {
  let assert Ok(Nil) =
    with_server("kill", fn(port) {
      let notices = process.new_subject()
      let assert Ok(started) =
        websocket_actor.start("127.0.0.1", port, "/echo", options(), notices)
      let monitor = process.monitor(started.pid)
      let assert Ok(Nil) = kill_connection(started.pid)
      let assert Ok(websocket_actor.Failed(error.ConnectionDown(_))) =
        process.receive(notices, 1000)
      await_exit(monitor)
      Ok(Nil)
    })
  Nil
}

fn await_exit(monitor: process.Monitor) -> Nil {
  let selector =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(down) { down })
  let assert Ok(process.ProcessDown(_, _, process.Normal)) =
    process.selector_receive(selector, 1000)
  Nil
}

fn options() -> websocket.UpgradeOptions {
  websocket.upgrade_options()
}

@external(erlang, "actor_peer", "release_disconnect")
fn release_disconnect() -> Nil

@external(erlang, "actor_peer", "kill_connection")
fn kill_connection(pid: process.Pid) -> Result(Nil, error.GluegunError)

@external(erlang, "actor_peer", "with_server")
fn with_server(
  mode: String,
  callback: fn(Int) -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

@external(erlang, "actor_peer", "assert_owner")
fn assert_owner(pid: process.Pid) -> Result(Nil, error.GluegunError)
