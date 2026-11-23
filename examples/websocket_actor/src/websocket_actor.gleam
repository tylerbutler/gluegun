import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/otp/actor
import gleam/result
import gleam/string
import gluegun/connection
import gluegun/error
import gluegun/message
import gluegun/websocket

pub type Command {
  SendText(text: String, reply: Subject(Result(Nil, error.GluegunError)))
  Inspect(reply: Subject(Nil))
  Close(reply: Subject(Result(Nil, error.GluegunError)))
  Gun(Result(message.Event, error.GluegunError))
  ConnectionExited(process.Down)
}

pub type Notice {
  FrameReceived(message.Frame)
  Lifecycle(message.Event)
  Failed(error.GluegunError)
}

type State {
  State(
    socket: websocket.Socket,
    monitor: process.Monitor,
    notices: Subject(Notice),
  )
}

/// Open and own Gun inside actor init. The loop receives Gun events and
/// application commands through one selector, without caller Erlang FFI.
pub fn start(
  host: String,
  port: Int,
  path: String,
  upgrade_options: websocket.UpgradeOptions,
  notices: Subject(Notice),
) -> actor.StartResult(Subject(Command)) {
  actor.new_with_initialiser(11_000, fn(commands) {
    use source <- result.try(
      connection.options()
      |> connection.with_protocols([connection.Http1])
      |> connection.open(host:, port:)
      |> result.map_error(string.inspect),
    )
    let monitor = connection.monitor(source)
    let timeout = connection.default_timeout()
    let setup = {
      use protocol <- result.try(connection.await_up(source, timeout))
      use stream <- result.try(websocket.upgrade(
        source,
        protocol,
        path,
        [],
        upgrade_options,
      ))
      use handshake <- result.try(websocket.await_upgrade(
        source,
        stream,
        timeout,
      ))
      Ok(websocket.from_upgrade(source, stream, handshake, timeout))
    }
    case setup {
      Ok(socket) -> {
        let selector =
          process.new_selector()
          |> process.select(commands)
          |> message.select(Gun)
          |> process.select_specific_monitor(monitor, ConnectionExited)
        Ok(
          actor.initialised(State(socket, monitor, notices))
          |> actor.selecting(selector)
          |> actor.returning(commands),
        )
      }
      Error(error) -> {
        process.demonitor_process(monitor)
        case connection.terminate(source) {
          Ok(Nil) -> Nil
          Error(cleanup_error) -> process.send(notices, Failed(cleanup_error))
        }
        Error(string.inspect(error))
      }
    }
  })
  |> actor.on_message(handle)
  |> actor.start
}

fn handle(state: State, command: Command) -> actor.Next(State, Command) {
  case command {
    SendText(text, reply) -> {
      process.send(reply, websocket.send_text(state.socket, text))
      actor.continue(state)
    }
    Inspect(reply) -> {
      process.send(reply, Nil)
      actor.continue(state)
    }
    Close(reply) -> {
      process.demonitor_process(state.monitor)
      process.send(reply, websocket.close(state.socket))
      actor.stop()
    }
    Gun(Ok(message.StreamMessage(envelope))) -> {
      case websocket.record_frame(state.socket, envelope) {
        Ok(frame) -> {
          process.send(state.notices, FrameReceived(frame))
          actor.continue(state)
        }
        Error(error) -> fail(state, error)
      }
    }
    Gun(Ok(message.ConnectionDown(_, _, _, _) as event)) -> {
      process.send(state.notices, Lifecycle(event))
      stop_socket(state)
    }
    Gun(Ok(message.ConnectionUp(_, _) as event))
    | Gun(Ok(message.TunnelUp(_, _, _) as event)) -> {
      process.send(state.notices, Lifecycle(event))
      actor.continue(state)
    }
    Gun(Ok(message.StreamFailure(_, _, error)))
    | Gun(Ok(message.ConnectionFailure(_, error)))
    | Gun(Error(error)) -> fail(state, error)
    ConnectionExited(process.ProcessDown(_, _, reason)) ->
      fail(state, error.ConnectionDown(string.inspect(reason)))
    ConnectionExited(process.PortDown(_, _, _)) ->
      fail(state, error.InvalidMessage("expected a Gun process monitor"))
  }
}

fn fail(state: State, error: error.GluegunError) -> actor.Next(State, Command) {
  process.send(state.notices, Failed(error))
  stop_socket(state)
}

fn stop_socket(state: State) -> actor.Next(State, Command) {
  process.demonitor_process(state.monitor)
  case websocket.close(state.socket) {
    Ok(Nil) -> Nil
    Error(error) -> process.send(state.notices, Failed(error))
  }
  actor.stop()
}

pub fn main() -> Nil {
  let notices = process.new_subject()
  let assert Ok(started) =
    start("localhost", 8080, "/echo", websocket.upgrade_options(), notices)
  let assert Ok(Nil) = process.call(started.data, 2000, SendText("hello", _))
  let assert Ok(FrameReceived(message.Text(reply))) =
    process.receive(notices, 2000)
  io.println(reply)
  let assert Ok(Nil) = process.call(started.data, 2000, Close)
  Nil
}
