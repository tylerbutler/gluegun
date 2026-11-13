import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/message
import gluegun/request

pub fn await_up_zero_test() -> Nil {
  accepted(Up, finite(0))
}

pub fn await_up_max_test() -> Nil {
  accepted(Up, finite(4_294_967_295))
}

pub fn await_up_infinity_test() -> Nil {
  accepted(Up, connection.infinity())
}

pub fn await_up_negative_test() -> Nil {
  rejected(Up, -1)
}

pub fn await_up_above_max_test() -> Nil {
  rejected(Up, 4_294_967_296)
}

pub fn await_zero_test() -> Nil {
  accepted(Message, finite(0))
}

pub fn await_max_test() -> Nil {
  accepted(Message, finite(4_294_967_295))
}

pub fn await_infinity_test() -> Nil {
  accepted(Message, connection.infinity())
}

pub fn await_negative_test() -> Nil {
  rejected(Message, -1)
}

pub fn await_above_max_test() -> Nil {
  rejected(Message, 4_294_967_296)
}

pub fn await_body_zero_test() -> Nil {
  accepted(Body, finite(0))
}

pub fn await_body_max_test() -> Nil {
  accepted(Body, finite(4_294_967_295))
}

pub fn await_body_infinity_test() -> Nil {
  accepted(Body, connection.infinity())
}

pub fn await_body_negative_test() -> Nil {
  rejected(Body, -1)
}

pub fn await_body_above_max_test() -> Nil {
  rejected(Body, 4_294_967_296)
}

pub fn ws_await_zero_test() -> Nil {
  accepted(Websocket, finite(0))
}

pub fn ws_await_max_test() -> Nil {
  accepted(Websocket, finite(4_294_967_295))
}

pub fn ws_await_infinity_test() -> Nil {
  accepted(Websocket, connection.infinity())
}

pub fn ws_await_negative_test() -> Nil {
  rejected(Websocket, -1)
}

pub fn ws_await_above_max_test() -> Nil {
  rejected(Websocket, 4_294_967_296)
}

pub fn ws_close_negative_has_no_side_effects_test() -> Nil {
  let assert Error(error.InvalidOptions(_)) = rejected_close(-1)
  Nil
}

pub fn ws_close_above_max_has_no_side_effects_test() -> Nil {
  let assert Error(error.InvalidOptions(_)) = rejected_close(4_294_967_296)
  Nil
}

pub fn timeout_options_negative_test() -> Nil {
  assert_rejected_options(-1)
}

pub fn timeout_options_above_max_test() -> Nil {
  assert_rejected_options(4_294_967_296)
}

fn finite(value: Int) -> connection.Timeout {
  let assert Ok(timeout) = connection.milliseconds(value)
  timeout
}

fn accepted(kind: Fixture, timeout: connection.Timeout) -> Nil {
  use connection, stream <- with_fixture(kind, True)
  case kind {
    Up -> {
      let assert Ok(connection.Http1) = connection.await_up(connection, timeout)
      Nil
    }
    Message -> {
      let assert Ok(message.Data(fin.Fin, <<"body":utf8>>)) =
        message.await(connection, stream, timeout)
      Nil
    }
    Body -> {
      let assert Ok(<<"body":utf8>>) =
        message.await_body(connection, stream, timeout)
      Nil
    }
    Websocket -> {
      let assert Ok(message.WebSocket(message.Text("hello"))) =
        ws_await(connection, stream, timeout)
      Nil
    }
  }
}

fn rejected(kind: Fixture, value: Int) -> Nil {
  let timeout = unchecked_milliseconds(value)
  use connection, stream <- with_fixture(kind, False)
  case kind {
    Up -> {
      let assert Error(error.InvalidOptions(_)) =
        connection.await_up(connection, timeout)
      Nil
    }
    Message -> {
      let assert Error(error.InvalidOptions(_)) =
        message.await(connection, stream, timeout)
      Nil
    }
    Body -> {
      let assert Error(error.InvalidOptions(_)) =
        message.await_body(connection, stream, timeout)
      Nil
    }
    Websocket -> {
      let assert Error(error.InvalidOptions(_)) =
        ws_await(connection, stream, timeout)
      Nil
    }
  }
}

type Fixture {
  Up
  Message
  Body
  Websocket
}

@external(erlang, "gluegun_timeout_test", "unchecked_milliseconds")
fn unchecked_milliseconds(value: Int) -> connection.Timeout

@external(erlang, "gluegun_timeout_test", "with_fixture")
fn with_fixture(
  kind: Fixture,
  consumed: Bool,
  callback: fn(connection.Connection, request.Stream) -> Nil,
) -> Nil

@external(erlang, "gluegun_ffi", "ws_await")
fn ws_await(
  connection: connection.Connection,
  stream: request.Stream,
  timeout: connection.Timeout,
) -> Result(message.Message, error.GluegunError)

@external(erlang, "gluegun_timeout_test", "rejected_close")
fn rejected_close(value: Int) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_timeout_test", "assert_rejected_options")
fn assert_rejected_options(value: Int) -> Nil
