import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/internal
import gluegun/message

pub fn open_returned_options_error_test() -> Nil {
  let assert True =
    invalid_open_options()
    == Error(error.InvalidOptions("Protocols([Http, Http])"))
  Nil
}

pub fn await_up_dead_connection_test() -> Nil {
  let assert True =
    connection.await_up(dead_connection(), connection.default_timeout())
    == Error(error.ConnectionDown("Noproc"))
  Nil
}

pub fn await_dead_connection_test() -> Nil {
  let assert True =
    message.await(dead_connection(), stream_ref(), connection.default_timeout())
    == Error(error.ConnectionDown("Noproc"))
  Nil
}

pub fn await_body_dead_connection_test() -> Nil {
  let assert True =
    message.await_body(
      dead_connection(),
      stream_ref(),
      connection.default_timeout(),
    )
    == Error(error.ConnectionDown("Noproc"))
  Nil
}

pub fn await_stream_error_test() -> Nil {
  let connection = current_connection()
  let stream = stream_ref()
  seed_message(stream_error_message(connection, stream))
  let assert True =
    message.await(connection, stream, zero())
    == Error(error.StreamError("Boom"))
  Nil
}

pub fn await_connection_error_test() -> Nil {
  let connection = current_connection()
  let stream = stream_ref()
  seed_message(connection_error_message(connection))
  let assert True =
    message.await(connection, stream, zero())
    == Error(error.ConnectionError("Boom"))
  Nil
}

pub fn await_body_stream_error_test() -> Nil {
  let connection = current_connection()
  let stream = stream_ref()
  seed_message(stream_error_message(connection, stream))
  let assert True =
    message.await_body(connection, stream, zero())
    == Error(error.StreamError("Boom"))
  Nil
}

pub fn await_body_connection_error_test() -> Nil {
  let connection = current_connection()
  let stream = stream_ref()
  seed_message(connection_error_message(connection))
  let assert True =
    message.await_body(connection, stream, zero())
    == Error(error.ConnectionError("Boom"))
  Nil
}

pub fn await_retains_nested_stream_reason_test() -> Nil {
  let connection = current_connection()
  let stream = stream_ref()
  seed_message(nested_stream_error_message(connection, stream))
  let assert True =
    message.await(connection, stream, zero())
    == Error(error.StreamError("StreamError(Boom)"))
  Nil
}

pub fn await_body_retains_nested_connection_reason_test() -> Nil {
  let connection = current_connection()
  let stream = stream_ref()
  seed_message(nested_connection_error_message(connection))
  let assert True =
    message.await_body(connection, stream, zero())
    == Error(error.ConnectionError("ConnectionError(Boom)"))
  Nil
}

pub fn await_up_timeout_test() -> Nil {
  let assert True =
    connection.await_up(current_connection(), zero()) == Error(error.Timeout)
  Nil
}

pub fn await_timeout_test() -> Nil {
  let assert True =
    message.await(current_connection(), stream_ref(), zero())
    == Error(error.Timeout)
  Nil
}

pub fn await_body_timeout_test() -> Nil {
  let assert True =
    message.await_body(current_connection(), stream_ref(), zero())
    == Error(error.Timeout)
  Nil
}

pub fn decode_mailbox_stream_error_test() -> Nil {
  let assert True =
    message.decode(stream_error_message(current_connection(), stream_ref()))
    == Error(error.StreamError("Boom"))
  Nil
}

pub fn decode_mailbox_connection_error_test() -> Nil {
  let assert True =
    message.decode(connection_error_message(current_connection()))
    == Error(error.ConnectionError("Boom"))
  Nil
}

pub fn decode_tunneled_mailbox_stream_error_test() -> Nil {
  let assert True =
    message.decode(stream_error_message(
      current_connection(),
      tunneled_stream_ref(),
    ))
    == Error(error.StreamError("Boom"))
  Nil
}

pub fn decode_mailbox_down_test() -> Nil {
  let assert True =
    message.decode(down_message(current_connection()))
    == Error(error.ConnectionDown("Boom"))
  Nil
}

pub fn decode_retains_nested_stream_reason_test() -> Nil {
  let assert True =
    message.decode(nested_stream_error_message(
      current_connection(),
      stream_ref(),
    ))
    == Error(error.StreamError("StreamError(Boom)"))
  Nil
}

pub fn decode_retains_nested_connection_reason_test() -> Nil {
  let assert True =
    message.decode(nested_connection_error_message(current_connection()))
    == Error(error.ConnectionError("ConnectionError(Boom)"))
  Nil
}

pub fn decode_malformed_error_identity_test() -> Nil {
  let assert True =
    message.decode(malformed_stream_error_message())
    == Error(error.DecodeError("Invalid Gun message"))
  Nil
}

pub fn decode_malformed_down_arity_test() -> Nil {
  let assert True =
    message.decode(malformed_down_message(current_connection()))
    == Error(error.DecodeError("Invalid Gun message"))
  Nil
}

pub fn decode_malformed_success_payload_test() -> Nil {
  let assert True =
    message.decode(malformed_response_message(
      current_connection(),
      stream_ref(),
    ))
    == Error(error.DecodeError("Invalid Gun message"))
  Nil
}

pub fn decode_preserves_success_envelope_identity_test() -> Nil {
  let connection = current_connection()
  let stream = stream_ref()
  let assert True =
    message.decode(
      mailbox_response_message(connection, stream, fin.Fin, 200, [
        #("Server", "gun"),
      ]),
    )
    == Ok(message.Envelope(
      connection,
      stream,
      message.Response(fin.Fin, 200, [#("server", "gun")]),
    ))
  Nil
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
  connection: internal.Connection,
  stream: internal.Stream,
) -> message.GunMessage

@external(erlang, "gluegun_error_normalization_test", "connection_error_message")
fn connection_error_message(
  connection: internal.Connection,
) -> message.GunMessage

@external(erlang, "gluegun_error_normalization_test", "down_message")
fn down_message(connection: internal.Connection) -> message.GunMessage

@external(erlang, "gluegun_error_normalization_test", "nested_stream_error_message")
fn nested_stream_error_message(
  connection: internal.Connection,
  stream: internal.Stream,
) -> message.GunMessage

@external(erlang, "gluegun_error_normalization_test", "nested_connection_error_message")
fn nested_connection_error_message(
  connection: internal.Connection,
) -> message.GunMessage

@external(erlang, "gluegun_error_normalization_test", "malformed_stream_error_message")
fn malformed_stream_error_message() -> message.GunMessage

@external(erlang, "gluegun_error_normalization_test", "malformed_down_message")
fn malformed_down_message(connection: internal.Connection) -> message.GunMessage

@external(erlang, "gluegun_error_normalization_test", "seed_message")
fn seed_message(value: message.GunMessage) -> Nil

@external(erlang, "gluegun_error_normalization_test", "malformed_response_message")
fn malformed_response_message(
  connection: internal.Connection,
  stream: internal.Stream,
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "mailbox_response_message")
fn mailbox_response_message(
  connection: internal.Connection,
  stream: internal.Stream,
  fin: fin.Fin,
  status: Int,
  headers: List(#(String, String)),
) -> message.GunMessage
