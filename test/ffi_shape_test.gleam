import gleam/http
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/internal
import gluegun/message

pub fn typed_option_conversion_converts_timeouts_test() -> Nil {
  let assert Ok(retries) = connection.retry_count(123)
  let actual_1 = {
    connection.options()
    |> connection.with_retry(retries)
    |> connection.with_connect_timeout(connection.infinity())
    |> connection.options_to_ffi
    |> gun_retry_and_connect_timeout
  }
  let expected_1 = #("123", "infinity")
  let assert #(True, _, _) = #(actual_1 == expected_1, actual_1, expected_1)
  Nil
}

pub fn typed_option_conversion_rejects_negative_timeouts_test() -> Nil {
  let actual_2 = connection.milliseconds(-1)
  let expected_2 = Error(error.InvalidOptions("timeout must be non-negative"))
  let assert #(True, _, _) = #(actual_2 == expected_2, actual_2, expected_2)
  Nil
}

pub fn typed_option_conversion_accepts_zero_timeout_test() -> Nil {
  let assert Ok(_) = connection.milliseconds(0)
  Nil
}

pub fn typed_option_conversion_accepts_maximum_timeout_test() -> Nil {
  let assert Ok(_) = connection.milliseconds(4_294_967_295)
  Nil
}

pub fn typed_option_conversion_rejects_oversized_timeout_test() -> Nil {
  let assert Error(error.InvalidOptions(_)) =
    connection.milliseconds(4_294_967_296)
  Nil
}

pub fn typed_option_conversion_preserves_protocol_ordering_test() -> Nil {
  let actual_3 = {
    connection.options()
    |> connection.with_protocols([connection.Http2, connection.Http1])
    |> connection.options_to_ffi
    |> gun_protocols
  }
  let expected_3 = ["http2", "http"]
  let assert #(True, _, _) = #(actual_3 == expected_3, actual_3, expected_3)
  Nil
}

pub fn message_and_error_shapes_preserves_invalid_await_up_protocol_decode_errors_test() -> Nil {
  let actual_4 = gun_protocol_result("spdy")
  let expected_4 = Error(error.DecodeError("Invalid protocol"))
  let assert #(True, _, _) = #(actual_4 == expected_4, actual_4, expected_4)
  Nil
}

pub fn message_and_error_shapes_maps_timeout_errors_test() -> Nil {
  let actual_5 = gluegun_ffi_test_timeout_error()
  let expected_5 = Error(error.Timeout)
  let assert #(True, _, _) = #(actual_5 == expected_5, actual_5, expected_5)
  Nil
}

pub fn message_and_error_shapes_decodes_response_message_shapes_test() -> Nil {
  let actual_6 = {
    gluegun_ffi_test_response_message(fin.Fin, 200, [
      #("Content-Type", "text/plain"),
    ])
    |> safe_decode_message
  }
  let expected_6 =
    Ok(message.Response(fin.Fin, 200, [#("content-type", "text/plain")]))
  let assert #(True, _, _) = #(actual_6 == expected_6, actual_6, expected_6)
  Nil
}

pub fn message_and_error_shapes_decodes_binary_body_data_message_shapes_test() -> Nil {
  let actual_7 = {
    gluegun_ffi_test_data_message(fin.NoFin, <<"hello":utf8>>)
    |> safe_decode_message
  }
  let expected_7 = Ok(message.Data(fin.NoFin, <<"hello":utf8>>))
  let assert #(True, _, _) = #(actual_7 == expected_7, actual_7, expected_7)
  Nil
}

pub fn message_and_error_shapes_keeps_gun_stream_references_intact_in_push_messages_test() -> Nil {
  let stream = gluegun_ffi_test_stream_ref()

  let actual_8 = {
    gluegun_ffi_test_push_message(stream, "GET", "/pushed", [])
    |> safe_decode_message
  }
  let expected_8 = Ok(message.Push(stream, http.Get, "/pushed", []))
  let assert #(True, _, _) = #(actual_8 == expected_8, actual_8, expected_8)
  Nil
}

pub fn message_and_error_shapes_decodes_flow_control_updates_as_nil_results_test() -> Nil {
  let actual_9 = gluegun_ffi_test_capture_update_flow(1234)
  let expected_9 = Ok(1234)
  let assert #(True, _, _) = #(actual_9 == expected_9, actual_9, expected_9)
  Nil
}

pub fn message_and_error_shapes_decodes_request_errors_instead_of_wrapping_them_as_streams_test() -> Nil {
  let actual_10 = gluegun_ffi_test_erlang_error()
  let expected_10 = Error(error.ErlangError("Error(FunctionClause)"))
  let assert #(True, _, _) = #(actual_10 == expected_10, actual_10, expected_10)
  Nil
}

pub fn message_and_error_shapes_surfaces_non_binary_request_fields_as_erlangerror_instead_of_crashing_test() -> Nil {
  let actual_11 = gluegun_ffi_test_invalid_binary_method()
  let expected_11 = Error(error.ErlangError("Error(InvalidBinary(3.14))"))
  let assert #(True, _, _) = #(actual_11 == expected_11, actual_11, expected_11)
  Nil
}

pub fn message_and_error_shapes_keeps_stream_errors_explicit_test() -> Nil {
  let actual_12 = gluegun_ffi_test_stream_error()
  let expected_12 = Error(error.StreamError("Boom"))
  let assert #(True, _, _) = #(actual_12 == expected_12, actual_12, expected_12)
  Nil
}

pub fn message_and_error_shapes_keeps_close_errors_explicit_test() -> Nil {
  let actual_13 = {
    gluegun_ffi_test_invalid_connection()
    |> connection.close
  }
  let expected_13 = Error(error.ConnectionError("Error(SimpleOneForOne)"))
  let assert #(True, _, _) = #(actual_13 == expected_13, actual_13, expected_13)
  Nil
}

pub fn message_and_error_shapes_keeps_shutdown_errors_explicit_test() -> Nil {
  let actual_14 = {
    gluegun_ffi_test_invalid_connection()
    |> connection.shutdown
  }
  let expected_14 = Error(error.ConnectionError("Error(FunctionClause)"))
  let assert #(True, _, _) = #(actual_14 == expected_14, actual_14, expected_14)
  Nil
}

pub fn message_and_error_shapes_rejects_invalid_utf_8_websocket_text_test() -> Nil {
  let actual_15 = gluegun_ffi_test_invalid_utf8_websocket()
  let expected_15 = Error(error.DecodeError("InvalidUtf8"))
  let assert #(True, _, _) = #(actual_15 == expected_15, actual_15, expected_15)
  Nil
}

pub fn gun_mailbox_messages_decodes_gun_inform_mailbox_tuples_test() -> Nil {
  let connection = current_connection()
  let stream = gluegun_ffi_test_stream_ref()

  let actual_16 = {
    mailbox_inform_message(connection, stream, 103, [
      #("Link", "</style.css>"),
    ])
    |> message.decode
  }
  let expected_16 =
    Ok(message.Envelope(
      connection,
      stream,
      message.Inform(103, [#("link", "</style.css>")]),
    ))
  let assert #(True, _, _) = #(actual_16 == expected_16, actual_16, expected_16)
  Nil
}

pub fn gun_mailbox_messages_decodes_gun_response_mailbox_tuples_test() -> Nil {
  let connection = current_connection()
  let stream = gluegun_ffi_test_stream_ref()

  let actual_17 = {
    mailbox_response_message(connection, stream, fin.NoFin, 200, [
      #("Server", "gun"),
    ])
    |> message.decode
  }
  let expected_17 =
    Ok(message.Envelope(
      connection,
      stream,
      message.Response(fin.NoFin, 200, [#("server", "gun")]),
    ))
  let assert #(True, _, _) = #(actual_17 == expected_17, actual_17, expected_17)
  Nil
}

pub fn gun_mailbox_messages_decodes_gun_data_mailbox_tuples_test() -> Nil {
  let connection = current_connection()
  let stream = gluegun_ffi_test_stream_ref()

  let actual_18 = {
    mailbox_data_message(connection, stream, fin.Fin, <<"hello":utf8>>)
    |> message.decode
  }
  let expected_18 =
    Ok(message.Envelope(
      connection,
      stream,
      message.Data(fin.Fin, <<"hello":utf8>>),
    ))
  let assert #(True, _, _) = #(actual_18 == expected_18, actual_18, expected_18)
  Nil
}

pub fn gun_mailbox_messages_decodes_gun_trailers_mailbox_tuples_test() -> Nil {
  let connection = current_connection()
  let stream = gluegun_ffi_test_stream_ref()

  let actual_19 = {
    mailbox_trailers_message(connection, stream, [#("Expires", "soon")])
    |> message.decode
  }
  let expected_19 =
    Ok(message.Envelope(
      connection,
      stream,
      message.Trailers([#("expires", "soon")]),
    ))
  let assert #(True, _, _) = #(actual_19 == expected_19, actual_19, expected_19)
  Nil
}

pub fn gun_mailbox_messages_decodes_gun_push_mailbox_tuples_test() -> Nil {
  let connection = current_connection()
  let stream = gluegun_ffi_test_stream_ref()
  let pushed = gluegun_ffi_test_stream_ref()

  let actual_20 = {
    mailbox_push_message(connection, stream, pushed, "GET", "/assets/app.css", [
      #("Accept", "text/css"),
    ])
    |> message.decode
  }
  let expected_20 =
    Ok(message.Envelope(
      connection,
      stream,
      message.Push(pushed, http.Get, "/assets/app.css", [
        #("accept", "text/css"),
      ]),
    ))
  let assert #(True, _, _) = #(actual_20 == expected_20, actual_20, expected_20)
  Nil
}

pub fn gun_mailbox_messages_decodes_gun_upgrade_mailbox_tuples_test() -> Nil {
  let connection = current_connection()
  let stream = gluegun_ffi_test_stream_ref()

  let actual_21 = {
    mailbox_upgrade_message(connection, stream, ["websocket"], [
      #("Connection", "Upgrade"),
    ])
    |> message.decode
  }
  let expected_21 =
    Ok(message.Envelope(
      connection,
      stream,
      message.Upgrade(["websocket"], [#("connection", "Upgrade")]),
    ))
  let assert #(True, _, _) = #(actual_21 == expected_21, actual_21, expected_21)
  Nil
}

pub fn gun_mailbox_messages_decodes_gun_ws_mailbox_tuples_test() -> Nil {
  let connection = current_connection()
  let stream = gluegun_ffi_test_stream_ref()

  let actual_22 = {
    mailbox_websocket_frame_message(
      connection,
      stream,
      gluegun_ffi_test_text_frame(<<"hello":utf8>>),
    )
    |> message.decode
  }
  let expected_22 =
    Ok(message.Envelope(
      connection,
      stream,
      message.WebSocket(message.Text("hello")),
    ))
  let assert #(True, _, _) = #(actual_22 == expected_22, actual_22, expected_22)
  Nil
}

pub fn gun_mailbox_messages_maps_stream_level_gun_error_tuples_test() -> Nil {
  let actual_23 = mailbox_stream_error_result()
  let expected_23 = Error(error.StreamError("Boom"))
  let assert #(True, _, _) = #(actual_23 == expected_23, actual_23, expected_23)
  Nil
}

pub fn gun_mailbox_messages_maps_connection_level_gun_error_tuples_test() -> Nil {
  let actual_24 = mailbox_connection_error_result()
  let expected_24 = Error(error.ConnectionError("Boom"))
  let assert #(True, _, _) = #(actual_24 == expected_24, actual_24, expected_24)
  Nil
}

pub fn gun_mailbox_messages_rejects_gun_await_3_style_terms_with_no_embedded_stream_test() -> Nil {
  let actual_25 = {
    gluegun_ffi_test_response_message(fin.Fin, 200, [])
    |> message.decode
  }
  let expected_25 = Error(error.DecodeError("Invalid Gun message"))
  let assert #(True, _, _) = #(actual_25 == expected_25, actual_25, expected_25)
  Nil
}

pub fn gun_mailbox_messages_collapses_a_malformed_payload_in_a_recognized_mailbox_tuple_to_a_generic_decode_error_test() -> Nil {
  let connection = current_connection()
  let stream = gluegun_ffi_test_stream_ref()

  let actual_26 = {
    mailbox_websocket_frame_message(
      connection,
      stream,
      gluegun_ffi_test_unknown_frame(),
    )
    |> message.decode
  }
  let expected_26 = Error(error.DecodeError("Invalid Gun message"))
  let assert #(True, _, _) = #(actual_26 == expected_26, actual_26, expected_26)
  Nil
}

pub fn gun_mailbox_messages_keeps_two_concurrent_streams_on_the_same_connection_distinct_test() -> Nil {
  let connection = current_connection()
  let stream_a = gluegun_ffi_test_stream_ref()
  let stream_b = gluegun_ffi_test_stream_ref()

  let assert Ok(message.Envelope(
    connection: envelope_a_connection,
    stream: envelope_a_stream,
    message: message_a,
  )) =
    mailbox_response_message(connection, stream_a, fin.NoFin, 200, [])
    |> message.decode

  let assert Ok(message.Envelope(
    connection: envelope_b_connection,
    stream: envelope_b_stream,
    message: message_b,
  )) =
    mailbox_data_message(connection, stream_b, fin.Fin, <<"hi":utf8>>)
    |> message.decode

  let actual_27 = envelope_a_connection
  let expected_27 = connection
  let assert #(True, _, _) = #(actual_27 == expected_27, actual_27, expected_27)
  let actual_28 = envelope_b_connection
  let expected_28 = connection
  let assert #(True, _, _) = #(actual_28 == expected_28, actual_28, expected_28)
  let actual_29 = envelope_a_stream
  let expected_29 = stream_a
  let assert #(True, _, _) = #(actual_29 == expected_29, actual_29, expected_29)
  let actual_30 = envelope_b_stream
  let expected_30 = stream_b
  let assert #(True, _, _) = #(actual_30 == expected_30, actual_30, expected_30)
  let actual_31 = envelope_a_stream
  let expected_31 = envelope_b_stream
  let assert #(True, _, _) = #(actual_31 != expected_31, actual_31, expected_31)
  let actual_32 = message_a
  let expected_32 = message.Response(fin.NoFin, 200, [])
  let assert #(True, _, _) = #(actual_32 == expected_32, actual_32, expected_32)
  let actual_33 = message_b
  let expected_33 = message.Data(fin.Fin, <<"hi":utf8>>)
  let assert #(True, _, _) = #(actual_33 == expected_33, actual_33, expected_33)
  Nil
}

pub fn gun_mailbox_messages_attributes_a_server_push_to_its_owning_stream_not_the_pushed_stream_test() -> Nil {
  let connection = current_connection()
  let owning_stream = gluegun_ffi_test_stream_ref()
  let pushed_stream = gluegun_ffi_test_stream_ref()

  let actual_34 = {
    mailbox_push_message(
      connection,
      owning_stream,
      pushed_stream,
      "GET",
      "/assets/app.css",
      [],
    )
    |> message.decode
  }
  let expected_34 =
    Ok(message.Envelope(
      connection,
      owning_stream,
      message.Push(pushed_stream, http.Get, "/assets/app.css", []),
    ))
  let assert #(True, _, _) = #(actual_34 == expected_34, actual_34, expected_34)
  Nil
}

pub fn collected_response_bodies_returns_the_body_when_the_last_chunk_carries_fin_test() -> Nil {
  let actual_35 = await_body_with_fin(<<"hello":utf8>>)
  let expected_35 = Ok(<<"hello":utf8>>)
  let assert #(True, _, _) = #(actual_35 == expected_35, actual_35, expected_35)
  Nil
}

pub fn collected_response_bodies_returns_the_body_when_the_response_ends_in_trailers_test() -> Nil {
  let actual_36 =
    await_body_with_trailers(<<"hello":utf8>>, [#("Expires", "soon")])
  let expected_36 = Ok(<<"hello":utf8>>)
  let assert #(True, _, _) = #(actual_36 == expected_36, actual_36, expected_36)
  Nil
}

fn gun_retry_and_connect_timeout(
  options: List(connection.ConnectOption),
) -> #(String, String) {
  #(gun_retry(options), gun_connect_timeout(options))
}

@external(erlang, "gluegun_ffi_test", "gun_protocols")
fn gun_protocols(options: List(connection.ConnectOption)) -> List(String)

@external(erlang, "gluegun_ffi_test", "gun_retry")
fn gun_retry(options: List(connection.ConnectOption)) -> String

@external(erlang, "gluegun_ffi_test", "gun_connect_timeout")
fn gun_connect_timeout(options: List(connection.ConnectOption)) -> String

@external(erlang, "gluegun_ffi_test", "protocol_result")
fn gun_protocol_result(
  protocol: String,
) -> Result(connection.Protocol, error.GluegunError)

@external(erlang, "gluegun_ffi_test", "response_message")
fn gluegun_ffi_test_response_message(
  fin: fin.Fin,
  status: Int,
  headers: List(#(String, String)),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "data_message")
fn gluegun_ffi_test_data_message(
  fin: fin.Fin,
  data: BitArray,
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "push_message")
fn gluegun_ffi_test_push_message(
  stream: internal.Stream,
  method: String,
  uri: String,
  headers: List(#(String, String)),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "stream_ref")
fn gluegun_ffi_test_stream_ref() -> internal.Stream

@external(erlang, "gluegun_ffi_test", "invalid_connection")
fn gluegun_ffi_test_invalid_connection() -> internal.Connection

@external(erlang, "gluegun_ffi_test", "erlang_error_result")
fn gluegun_ffi_test_erlang_error() -> Result(
  internal.Stream,
  error.GluegunError,
)

@external(erlang, "gluegun_ffi_test", "invalid_binary_method_result")
fn gluegun_ffi_test_invalid_binary_method() -> Result(
  internal.Stream,
  error.GluegunError,
)

@external(erlang, "gluegun_ffi_test", "stream_error_result")
fn gluegun_ffi_test_stream_error() -> Result(
  message.Message,
  error.GluegunError,
)

@external(erlang, "gluegun_ffi_test", "timeout_error_result")
fn gluegun_ffi_test_timeout_error() -> Result(
  message.Message,
  error.GluegunError,
)

@external(erlang, "gluegun_ffi_test", "invalid_utf8_websocket_result")
fn gluegun_ffi_test_invalid_utf8_websocket() -> Result(
  message.Message,
  error.GluegunError,
)

@external(erlang, "gluegun_ffi_test", "capture_update_flow")
fn gluegun_ffi_test_capture_update_flow(
  increment: Int,
) -> Result(Int, error.GluegunError)

/// A raw Gun WebSocket frame term, as carried inside a `gun_ws` message.
type GunFrame

@external(erlang, "gluegun_ffi_test", "text_frame")
fn gluegun_ffi_test_text_frame(data: BitArray) -> GunFrame

@external(erlang, "gluegun_ffi_test", "unknown_frame")
fn gluegun_ffi_test_unknown_frame() -> GunFrame

@external(erlang, "gluegun_ffi_test", "mailbox_inform_message")
fn mailbox_inform_message(
  connection: internal.Connection,
  stream: internal.Stream,
  status: Int,
  headers: List(#(String, String)),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "mailbox_response_message")
fn mailbox_response_message(
  connection: internal.Connection,
  stream: internal.Stream,
  fin: fin.Fin,
  status: Int,
  headers: List(#(String, String)),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "mailbox_data_message")
fn mailbox_data_message(
  connection: internal.Connection,
  stream: internal.Stream,
  fin: fin.Fin,
  data: BitArray,
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "mailbox_trailers_message")
fn mailbox_trailers_message(
  connection: internal.Connection,
  stream: internal.Stream,
  headers: List(#(String, String)),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "mailbox_push_message")
fn mailbox_push_message(
  connection: internal.Connection,
  stream: internal.Stream,
  pushed_stream: internal.Stream,
  method: String,
  uri: String,
  headers: List(#(String, String)),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "mailbox_upgrade_message")
fn mailbox_upgrade_message(
  connection: internal.Connection,
  stream: internal.Stream,
  protocols: List(String),
  headers: List(#(String, String)),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "mailbox_websocket_frame_message")
fn mailbox_websocket_frame_message(
  connection: internal.Connection,
  stream: internal.Stream,
  frame: GunFrame,
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "mailbox_stream_error_result")
fn mailbox_stream_error_result() -> Result(message.Message, error.GluegunError)

@external(erlang, "gluegun_ffi_test", "mailbox_connection_error_result")
fn mailbox_connection_error_result() -> Result(
  message.Message,
  error.GluegunError,
)

@external(erlang, "gluegun_ffi_test", "current_connection")
fn current_connection() -> internal.Connection

@external(erlang, "gluegun_ffi", "safe_decode_message")
fn safe_decode_message(
  message: message.GunMessage,
) -> Result(message.Message, error.GluegunError)

@external(erlang, "gluegun_ffi_test", "await_body_with_fin")
fn await_body_with_fin(body: BitArray) -> Result(BitArray, error.GluegunError)

@external(erlang, "gluegun_ffi_test", "await_body_with_trailers")
fn await_body_with_trailers(
  body: BitArray,
  trailers: List(#(String, String)),
) -> Result(BitArray, error.GluegunError)
