import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/internal
import gluegun/message

pub fn open_returned_options_error_test() {
  let assert True =
    invalid_open_options()
    == Error(error.InvalidOptions("Protocols([Http, Http])"))
}

pub fn await_up_dead_connection_test() {
  let assert True =
    connection.await_up(dead_connection(), connection.default_timeout())
    == Error(error.ConnectionDown("Noproc"))
}

pub fn await_dead_connection_test() {
  let assert True =
    message.await(dead_connection(), stream_ref(), connection.default_timeout())
    == Error(error.ConnectionDown("Noproc"))
}

pub fn await_body_dead_connection_test() {
  let assert True =
    message.await_body(
      dead_connection(),
      stream_ref(),
      connection.default_timeout(),
    )
    == Error(error.ConnectionDown("Noproc"))
}

pub fn await_stream_error_test() {
  let conn = current_connection()
  let stream = stream_ref()
  seed_message(stream_error_message(conn, stream))
  let assert True =
    message.await(conn, stream, zero()) == Error(error.StreamError("Boom"))
}

pub fn await_connection_error_test() {
  let conn = current_connection()
  let stream = stream_ref()
  seed_message(connection_error_message(conn))
  let assert True =
    message.await(conn, stream, zero()) == Error(error.ConnectionError("Boom"))
}

pub fn await_body_stream_error_test() {
  let conn = current_connection()
  let stream = stream_ref()
  seed_message(stream_error_message(conn, stream))
  let assert True =
    message.await_body(conn, stream, zero()) == Error(error.StreamError("Boom"))
}

pub fn await_body_connection_error_test() {
  let conn = current_connection()
  let stream = stream_ref()
  seed_message(connection_error_message(conn))
  let assert True =
    message.await_body(conn, stream, zero())
    == Error(error.ConnectionError("Boom"))
}

pub fn await_retains_nested_stream_reason_test() {
  let conn = current_connection()
  let stream = stream_ref()
  seed_message(nested_stream_error_message(conn, stream))
  let assert True =
    message.await(conn, stream, zero())
    == Error(error.StreamError("StreamError(Boom)"))
}

pub fn await_body_retains_nested_connection_reason_test() {
  let conn = current_connection()
  let stream = stream_ref()
  seed_message(nested_connection_error_message(conn))
  let assert True =
    message.await_body(conn, stream, zero())
    == Error(error.ConnectionError("ConnectionError(Boom)"))
}

pub fn await_up_timeout_test() {
  let assert True =
    connection.await_up(current_connection(), zero()) == Error(error.Timeout)
}

pub fn await_timeout_test() {
  let assert True =
    message.await(current_connection(), stream_ref(), zero())
    == Error(error.Timeout)
}

pub fn await_body_timeout_test() {
  let assert True =
    message.await_body(current_connection(), stream_ref(), zero())
    == Error(error.Timeout)
}

pub fn decode_mailbox_stream_error_test() {
  let assert True =
    message.decode(stream_error_message(current_connection(), stream_ref()))
    == Error(error.StreamError("Boom"))
}

pub fn decode_mailbox_connection_error_test() {
  let assert True =
    message.decode(connection_error_message(current_connection()))
    == Error(error.ConnectionError("Boom"))
}

pub fn decode_tunneled_mailbox_stream_error_test() {
  let assert True =
    message.decode(stream_error_message(
      current_connection(),
      tunneled_stream_ref(),
    ))
    == Error(error.StreamError("Boom"))
}

pub fn decode_mailbox_down_test() {
  let assert True =
    message.decode(down_message(current_connection()))
    == Error(error.ConnectionDown("Boom"))
}

pub fn decode_retains_nested_stream_reason_test() {
  let assert True =
    message.decode(nested_stream_error_message(
      current_connection(),
      stream_ref(),
    ))
    == Error(error.StreamError("StreamError(Boom)"))
}

pub fn decode_retains_nested_connection_reason_test() {
  let assert True =
    message.decode(nested_connection_error_message(current_connection()))
    == Error(error.ConnectionError("ConnectionError(Boom)"))
}

pub fn decode_malformed_error_identity_test() {
  let assert True =
    message.decode(malformed_stream_error_message())
    == Error(error.DecodeError("Invalid Gun message"))
}

pub fn decode_malformed_down_arity_test() {
  let assert True =
    message.decode(malformed_down_message(current_connection()))
    == Error(error.DecodeError("Invalid Gun message"))
}

pub fn decode_malformed_success_payload_test() {
  let assert True =
    message.decode(malformed_response_message(
      current_connection(),
      stream_ref(),
    ))
    == Error(error.DecodeError("Invalid Gun message"))
}

pub fn decode_preserves_success_envelope_identity_test() {
  let conn = current_connection()
  let stream = stream_ref()
  let assert True =
    message.decode(
      mailbox_response_message(conn, stream, fin.Fin, 200, [#("Server", "gun")]),
    )
    == Ok(message.Envelope(
      conn,
      stream,
      message.Response(fin.Fin, 200, [#("server", "gun")]),
    ))
}

fn zero() -> connection.Timeout {
  let assert Ok(timeout) = connection.milliseconds(0)
  timeout
}

@external(erlang, "gluegun_error_normalization_test", "dead_connection")
fn dead_connection() -> internal.Connection

@external(erlang, "gluegun_error_normalization_test", "invalid_open_options")
fn invalid_open_options() -> Result(internal.Connection, error.GluegunError)

@external(erlang, "gluegun_ffi_test", "current_connection")
fn current_connection() -> internal.Connection

@external(erlang, "gluegun_ffi_test", "stream_ref")
fn stream_ref() -> internal.Stream

@external(erlang, "gluegun_error_normalization_test", "tunneled_stream_ref")
fn tunneled_stream_ref() -> internal.Stream

@external(erlang, "gluegun_error_normalization_test", "stream_error_message")
fn stream_error_message(
  conn: internal.Connection,
  stream: internal.Stream,
) -> message.GunMessage

@external(erlang, "gluegun_error_normalization_test", "connection_error_message")
fn connection_error_message(conn: internal.Connection) -> message.GunMessage

@external(erlang, "gluegun_error_normalization_test", "down_message")
fn down_message(conn: internal.Connection) -> message.GunMessage

@external(erlang, "gluegun_error_normalization_test", "nested_stream_error_message")
fn nested_stream_error_message(
  conn: internal.Connection,
  stream: internal.Stream,
) -> message.GunMessage

@external(erlang, "gluegun_error_normalization_test", "nested_connection_error_message")
fn nested_connection_error_message(
  conn: internal.Connection,
) -> message.GunMessage

@external(erlang, "gluegun_error_normalization_test", "malformed_stream_error_message")
fn malformed_stream_error_message() -> message.GunMessage

@external(erlang, "gluegun_error_normalization_test", "malformed_down_message")
fn malformed_down_message(conn: internal.Connection) -> message.GunMessage

@external(erlang, "gluegun_error_normalization_test", "seed_message")
fn seed_message(value: message.GunMessage) -> Nil

@external(erlang, "gluegun_error_normalization_test", "malformed_response_message")
fn malformed_response_message(
  conn: internal.Connection,
  stream: internal.Stream,
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "mailbox_response_message")
fn mailbox_response_message(
  conn: internal.Connection,
  stream: internal.Stream,
  fin: fin.Fin,
  status: Int,
  headers: List(#(String, String)),
) -> message.GunMessage
