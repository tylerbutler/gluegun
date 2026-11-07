/// Tests for WebSocket support: frame encoding/decoding, receive routing,
/// await_upgrade routing, and FFI shape validation.
///
/// Run this module with `gleam test -- --file test/websocket_test.gleam`.
import gleam/erlang/process
import gleam/option.{type Option, None, Some}
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/internal
import gluegun/message
import gluegun/websocket
import gluegun/websocket/raw

// ── Frame type variants ──────────────────────────────────────────────────────

pub fn frame_variants_supports_the_close_variant_test() -> Nil {
  let frame: message.Frame = message.Close
  let actual_1 = frame
  let expected_1 = message.Close
  let assert #(True, _, _) = #(actual_1 == expected_1, actual_1, expected_1)
  Nil
}

pub fn frame_variants_supports_close_with_reason_frames_test() -> Nil {
  let frame: message.Frame =
    message.CloseWithReason(1000, <<"normal closure":utf8>>)
  let actual_2 = frame
  let expected_2 = message.CloseWithReason(1000, <<"normal closure":utf8>>)
  let assert #(True, _, _) = #(actual_2 == expected_2, actual_2, expected_2)
  Nil
}

pub fn outbound_frame_encoding_encodes_text_frames_test() -> Nil {
  let actual_3 = {
    capture_ws_send_frame(message.Text("hello"))
    |> decode_captured_frame
  }
  let expected_3 = Ok(message.WebSocket(message.Text("hello")))
  let assert #(True, _, _) = #(actual_3 == expected_3, actual_3, expected_3)
  Nil
}

pub fn outbound_frame_encoding_encodes_binary_frames_test() -> Nil {
  let actual_4 = {
    capture_ws_send_frame(message.Binary(<<0, 1, 2, 255>>))
    |> decode_captured_frame
  }
  let expected_4 = Ok(message.WebSocket(message.Binary(<<0, 1, 2, 255>>)))
  let assert #(True, _, _) = #(actual_4 == expected_4, actual_4, expected_4)
  Nil
}

pub fn outbound_frame_encoding_encodes_ping_frames_test() -> Nil {
  let actual_5 = {
    capture_ws_send_frame(message.Ping(<<"ping":utf8>>))
    |> decode_captured_frame
  }
  let expected_5 = Ok(message.WebSocket(message.Ping(<<"ping":utf8>>)))
  let assert #(True, _, _) = #(actual_5 == expected_5, actual_5, expected_5)
  Nil
}

pub fn outbound_frame_encoding_encodes_pong_frames_test() -> Nil {
  let actual_6 = {
    capture_ws_send_frame(message.Pong(<<"pong":utf8>>))
    |> decode_captured_frame
  }
  let expected_6 = Ok(message.WebSocket(message.Pong(<<"pong":utf8>>)))
  let assert #(True, _, _) = #(actual_6 == expected_6, actual_6, expected_6)
  Nil
}

pub fn outbound_frame_encoding_encodes_plain_close_frames_test() -> Nil {
  let actual_7 = {
    capture_ws_send_frame(message.Close)
    |> decode_captured_frame
  }
  let expected_7 = Ok(message.WebSocket(message.Close))
  let assert #(True, _, _) = #(actual_7 == expected_7, actual_7, expected_7)
  Nil
}

pub fn outbound_frame_encoding_encodes_close_with_reason_frames_test() -> Nil {
  let actual_8 = {
    capture_ws_send_frame(
      message.CloseWithReason(1000, <<"normal closure":utf8>>),
    )
    |> decode_captured_frame
  }
  let expected_8 =
    Ok(
      message.WebSocket(
        message.CloseWithReason(1000, <<"normal closure":utf8>>),
      ),
    )
  let assert #(True, _, _) = #(actual_8 == expected_8, actual_8, expected_8)
  Nil
}

pub fn outbound_frame_encoding_encodes_multiple_frames_test() -> Nil {
  let test_connection = current_connection()
  let test_stream = stream_ref()

  let actual_9 =
    websocket.send_many(test_connection, test_stream, [
      message.Text("hello"),
      message.Binary(<<1, 2, 3>>),
      message.Ping(<<"ping":utf8>>),
    ])
  let expected_9 = Ok(Nil)
  let assert #(True, _, _) = #(actual_9 == expected_9, actual_9, expected_9)

  let actual_10 = capture_ws_send_frames()
  let expected_10 =
    Ok([
      #("text", <<"hello":utf8>>),
      #("binary", <<1, 2, 3>>),
      #("ping", <<"ping":utf8>>),
    ])
  let assert #(True, _, _) = #(actual_10 == expected_10, actual_10, expected_10)
  Nil
}

pub fn outbound_frame_encoding_surfaces_invalid_frame_list_errors_test() -> Nil {
  let actual_11 = invalid_ws_send_frame_list_result()
  let expected_11 = Error(error.InvalidMessage("InvalidFrame(BadFrame)"))
  let assert #(True, _, _) = #(actual_11 == expected_11, actual_11, expected_11)
  Nil
}

pub fn outbound_frame_encoding_surfaces_invalid_utf_8_text_send_errors_test() -> Nil {
  let actual_12 = invalid_ws_send_text_utf8_result()
  let expected_12 =
    Error(error.InvalidMessage("InvalidFrame(Text(InvalidUtf8))"))
  let assert #(True, _, _) = #(actual_12 == expected_12, actual_12, expected_12)
  Nil
}

pub fn inbound_frame_decoding_decodes_text_frames_test() -> Nil {
  let actual_13 = {
    websocket_frame_message(text_frame(<<"hello world":utf8>>))
    |> safe_decode_message
  }
  let expected_13 = Ok(message.WebSocket(message.Text("hello world")))
  let assert #(True, _, _) = #(actual_13 == expected_13, actual_13, expected_13)
  Nil
}

pub fn inbound_frame_decoding_decodes_binary_frames_test() -> Nil {
  let actual_14 = {
    websocket_frame_message(binary_frame(<<0, 1, 2, 255>>))
    |> safe_decode_message
  }
  let expected_14 = Ok(message.WebSocket(message.Binary(<<0, 1, 2, 255>>)))
  let assert #(True, _, _) = #(actual_14 == expected_14, actual_14, expected_14)
  Nil
}

pub fn inbound_frame_decoding_decodes_ping_frames_test() -> Nil {
  let actual_15 = {
    websocket_frame_message(ping_frame(<<>>))
    |> safe_decode_message
  }
  let expected_15 = Ok(message.WebSocket(message.Ping(<<>>)))
  let assert #(True, _, _) = #(actual_15 == expected_15, actual_15, expected_15)
  Nil
}

pub fn inbound_frame_decoding_decodes_pong_frames_test() -> Nil {
  let actual_16 = {
    websocket_frame_message(pong_frame(<<"keepalive":utf8>>))
    |> safe_decode_message
  }
  let expected_16 = Ok(message.WebSocket(message.Pong(<<"keepalive":utf8>>)))
  let assert #(True, _, _) = #(actual_16 == expected_16, actual_16, expected_16)
  Nil
}

pub fn inbound_frame_decoding_decodes_plain_close_frames_test() -> Nil {
  let actual_17 = {
    websocket_frame_message(close_frame())
    |> safe_decode_message
  }
  let expected_17 = Ok(message.WebSocket(message.Close))
  let assert #(True, _, _) = #(actual_17 == expected_17, actual_17, expected_17)
  Nil
}

pub fn inbound_frame_decoding_decodes_close_with_reason_frames_test() -> Nil {
  let actual_18 = {
    websocket_frame_message(
      close_with_reason_frame(1001, <<"going away":utf8>>),
    )
    |> safe_decode_message
  }
  let expected_18 =
    Ok(message.WebSocket(message.CloseWithReason(1001, <<"going away":utf8>>)))
  let assert #(True, _, _) = #(actual_18 == expected_18, actual_18, expected_18)
  Nil
}

pub fn ffi_close_frame_shapes_maps_plain_close_messages_safely_test() -> Nil {
  let actual_19 = {
    ws_close_message()
    |> safe_decode_message
  }
  let expected_19 = Ok(message.WebSocket(message.Close))
  let assert #(True, _, _) = #(actual_19 == expected_19, actual_19, expected_19)
  Nil
}

pub fn ffi_close_frame_shapes_maps_close_with_reason_messages_safely_test() -> Nil {
  let actual_20 = {
    ws_close_with_reason_message()
    |> safe_decode_message
  }
  let expected_20 =
    Ok(message.WebSocket(message.CloseWithReason(1001, <<"going away":utf8>>)))
  let assert #(True, _, _) = #(actual_20 == expected_20, actual_20, expected_20)
  Nil
}

pub fn receive_routing_accepts_websocket_text_messages_test() -> Nil {
  let actual_21 =
    websocket.receive_from(Ok(message.WebSocket(message.Text("hi"))))
  let expected_21 = Ok(message.Text("hi"))
  let assert #(True, _, _) = #(actual_21 == expected_21, actual_21, expected_21)
  Nil
}

pub fn receive_routing_accepts_websocket_binary_messages_test() -> Nil {
  let actual_22 =
    websocket.receive_from(Ok(message.WebSocket(message.Binary(<<1, 2, 3>>))))
  let expected_22 = Ok(message.Binary(<<1, 2, 3>>))
  let assert #(True, _, _) = #(actual_22 == expected_22, actual_22, expected_22)
  Nil
}

pub fn receive_routing_accepts_websocket_close_messages_test() -> Nil {
  let actual_23 = websocket.receive_from(Ok(message.WebSocket(message.Close)))
  let expected_23 = Ok(message.Close)
  let assert #(True, _, _) = #(actual_23 == expected_23, actual_23, expected_23)
  Nil
}

pub fn receive_routing_accepts_websocket_close_with_reason_messages_test() -> Nil {
  let actual_24 =
    websocket.receive_from(
      Ok(message.WebSocket(message.CloseWithReason(1000, <<"bye":utf8>>))),
    )
  let expected_24 = Ok(message.CloseWithReason(1000, <<"bye":utf8>>))
  let assert #(True, _, _) = #(actual_24 == expected_24, actual_24, expected_24)
  Nil
}

pub fn receive_routing_rejects_http_responses_test() -> Nil {
  let actual_25 = websocket.receive_from(Ok(message.Response(fin.Fin, 200, [])))
  let expected_25 =
    Error(error.InvalidMessage(
      "websocket.receive: expected WebSocket frame, got HTTP message",
    ))
  let assert #(True, _, _) = #(actual_25 == expected_25, actual_25, expected_25)
  Nil
}

pub fn receive_routing_rejects_http_data_test() -> Nil {
  let actual_26 =
    websocket.receive_from(Ok(message.Data(fin.Fin, <<"body":utf8>>)))
  let expected_26 =
    Error(error.InvalidMessage(
      "websocket.receive: expected WebSocket frame, got HTTP message",
    ))
  let assert #(True, _, _) = #(actual_26 == expected_26, actual_26, expected_26)
  Nil
}

pub fn receive_routing_rejects_upgrade_messages_test() -> Nil {
  let actual_27 = websocket.receive_from(Ok(message.Upgrade(["websocket"], [])))
  let expected_27 =
    Error(error.InvalidMessage(
      "websocket.receive: expected WebSocket frame, got Upgrade message; call await_upgrade first",
    ))
  let assert #(True, _, _) = #(actual_27 == expected_27, actual_27, expected_27)
  Nil
}

pub fn receive_routing_propagates_timeout_errors_test() -> Nil {
  let actual_28 = websocket.receive_from(Error(error.Timeout))
  let expected_28 = Error(error.Timeout)
  let assert #(True, _, _) = #(actual_28 == expected_28, actual_28, expected_28)
  Nil
}

pub fn receive_routing_propagates_stream_errors_test() -> Nil {
  let actual_29 = websocket.receive_from(Error(error.StreamError("closed")))
  let expected_29 = Error(error.StreamError("closed"))
  let assert #(True, _, _) = #(actual_29 == expected_29, actual_29, expected_29)
  Nil
}

pub fn websocket_socket_helpers_send_text_sends_text_through_the_wrapped_connection_and_stream_test() -> Nil {
  let socket =
    websocket.socket(current_connection(), stream_ref(), timeout(500))

  let actual_30 = websocket.send_text(socket, "hello")
  let expected_30 = Ok(Nil)
  let assert #(True, _, _) = #(actual_30 == expected_30, actual_30, expected_30)

  let actual_31 = capture_ws_send_frames()
  let expected_31 = Ok([#("text", <<"hello":utf8>>)])
  let assert #(True, _, _) = #(actual_31 == expected_31, actual_31, expected_31)
  Nil
}

pub fn websocket_socket_helpers_send_binary_sends_binary_through_the_wrapped_connection_and_stream_test() -> Nil {
  let socket =
    websocket.socket(current_connection(), stream_ref(), timeout(500))

  let actual_32 = websocket.send_binary(socket, <<1, 2, 3>>)
  let expected_32 = Ok(Nil)
  let assert #(True, _, _) = #(actual_32 == expected_32, actual_32, expected_32)

  let actual_33 = capture_ws_send_frames()
  let expected_33 = Ok([#("binary", <<1, 2, 3>>)])
  let assert #(True, _, _) = #(actual_33 == expected_33, actual_33, expected_33)
  Nil
}

pub fn websocket_socket_helpers_ping_sends_ping_through_the_wrapped_connection_and_stream_test() -> Nil {
  let socket =
    websocket.socket(current_connection(), stream_ref(), timeout(500))

  let actual_34 = websocket.ping(socket, <<"ping":utf8>>)
  let expected_34 = Ok(Nil)
  let assert #(True, _, _) = #(actual_34 == expected_34, actual_34, expected_34)

  let actual_35 = capture_ws_send_frames()
  let expected_35 = Ok([#("ping", <<"ping":utf8>>)])
  let assert #(True, _, _) = #(actual_35 == expected_35, actual_35, expected_35)
  Nil
}

pub fn websocket_socket_helpers_pong_sends_pong_through_the_wrapped_connection_and_stream_test() -> Nil {
  let socket =
    websocket.socket(current_connection(), stream_ref(), timeout(500))

  let actual_36 = websocket.pong(socket, <<"pong":utf8>>)
  let expected_36 = Ok(Nil)
  let assert #(True, _, _) = #(actual_36 == expected_36, actual_36, expected_36)

  let actual_37 = capture_ws_send_frames()
  let expected_37 = Ok([#("pong", <<"pong":utf8>>)])
  let assert #(True, _, _) = #(actual_37 == expected_37, actual_37, expected_37)
  Nil
}

pub fn websocket_socket_helpers_send_close_frame_sends_close_through_the_wrapped_connection_and_stream_test() -> Nil {
  let socket =
    websocket.socket(current_connection(), stream_ref(), timeout(500))

  let actual_38 = websocket.send_close_frame(socket)
  let expected_38 = Ok(Nil)
  let assert #(True, _, _) = #(actual_38 == expected_38, actual_38, expected_38)

  let actual_39 = capture_ws_send_frames()
  let expected_39 = Ok([#("close", <<>>)])
  let assert #(True, _, _) = #(actual_39 == expected_39, actual_39, expected_39)
  Nil
}

pub fn websocket_socket_helpers_receive_app_frame_returns_text_frames_test() -> Nil {
  let actual_40 = websocket.receive_app_frame_from([Ok(message.Text("hello"))])
  let expected_40 = Ok(message.Text("hello"))
  let assert #(True, _, _) = #(actual_40 == expected_40, actual_40, expected_40)
  Nil
}

pub fn websocket_socket_helpers_receive_app_frame_returns_binary_frames_test() -> Nil {
  let actual_41 =
    websocket.receive_app_frame_from([Ok(message.Binary(<<1, 2, 3>>))])
  let expected_41 = Ok(message.Binary(<<1, 2, 3>>))
  let assert #(True, _, _) = #(actual_41 == expected_41, actual_41, expected_41)
  Nil
}

pub fn websocket_socket_helpers_receive_app_frame_returns_close_frames_test() -> Nil {
  let actual_42 = websocket.receive_app_frame_from([Ok(message.Close)])
  let expected_42 = Ok(message.Close)
  let assert #(True, _, _) = #(actual_42 == expected_42, actual_42, expected_42)
  Nil
}

pub fn websocket_socket_helpers_receive_app_frame_returns_close_with_reason_frames_test() -> Nil {
  let actual_43 =
    websocket.receive_app_frame_from([
      Ok(message.CloseWithReason(1000, <<"bye":utf8>>)),
    ])
  let expected_43 = Ok(message.CloseWithReason(1000, <<"bye":utf8>>))
  let assert #(True, _, _) = #(actual_43 == expected_43, actual_43, expected_43)
  Nil
}

pub fn websocket_socket_helpers_receive_app_frame_skips_pong_frames_test() -> Nil {
  let actual_44 =
    websocket.receive_app_frame_from([
      Ok(message.Pong(<<"ignored":utf8>>)),
      Ok(message.Text("after pong")),
    ])
  let expected_44 = Ok(message.Text("after pong"))
  let assert #(True, _, _) = #(actual_44 == expected_44, actual_44, expected_44)
  Nil
}

pub fn websocket_socket_helpers_receive_app_frame_skips_ping_and_returns_the_next_app_frame_test() -> Nil {
  let actual_45 =
    websocket.receive_app_frame_from([
      Ok(message.Ping(<<"payload":utf8>>)),
      Ok(message.Text("after ping")),
    ])
  let expected_45 = Ok(message.Text("after ping"))
  let assert #(True, _, _) = #(actual_45 == expected_45, actual_45, expected_45)
  Nil
}

pub fn websocket_socket_helpers_receive_app_frame_returns_receive_errors_immediately_test() -> Nil {
  let actual_46 =
    websocket.receive_app_frame_from([
      Ok(message.Ping(<<"payload":utf8>>)),
      Error(error.StreamError("receive failed")),
      Ok(message.Text("unreached")),
    ])
  let expected_46 = Error(error.StreamError("receive failed"))
  let assert #(True, _, _) = #(actual_46 == expected_46, actual_46, expected_46)
  Nil
}

pub fn websocket_session_options_defaults_to_http_1_no_headers_default_upgrade_options_and_5000ms_timeout_test() -> Nil {
  let options = websocket.options()

  let actual_47 = {
    options
    |> websocket.options_connect_options
    |> connection.protocols
  }
  let expected_47 = Some([connection.Http1])
  let assert #(True, _, _) = #(actual_47 == expected_47, actual_47, expected_47)

  let actual_48 = {
    options
    |> websocket.options_headers
  }
  let expected_48 = []
  let assert #(True, _, _) = #(actual_48 == expected_48, actual_48, expected_48)

  let actual_49 = {
    options
    |> websocket.options_upgrade_options
    |> websocket.upgrade_options_to_ffi
  }
  let expected_49 = []
  let assert #(True, _, _) = #(actual_49 == expected_49, actual_49, expected_49)

  let actual_50 = {
    options
    |> websocket.options_timeout
  }
  let expected_50 = connection.default_timeout()
  let assert #(True, _, _) = #(actual_50 == expected_50, actual_50, expected_50)
  Nil
}

pub fn websocket_session_options_with_headers_updates_only_headers_test() -> Nil {
  let original = websocket.options()
  let updated =
    original
    |> websocket.with_headers([#("sec-websocket-protocol", "chat")])

  let actual_51 = {
    updated
    |> websocket.options_headers
  }
  let expected_51 = [#("sec-websocket-protocol", "chat")]
  let assert #(True, _, _) = #(actual_51 == expected_51, actual_51, expected_51)

  let actual_52 = {
    updated
    |> websocket.options_connect_options
    |> connection.protocols
  }
  let expected_52 = {
    original
    |> websocket.options_connect_options
    |> connection.protocols
  }
  let assert #(True, _, _) = #(actual_52 == expected_52, actual_52, expected_52)

  let actual_53 = {
    updated
    |> websocket.options_timeout
  }
  let expected_53 = websocket.options_timeout(original)
  let assert #(True, _, _) = #(actual_53 == expected_53, actual_53, expected_53)

  let actual_54 = {
    updated
    |> websocket.options_upgrade_options
    |> websocket.upgrade_options_to_ffi
  }
  let expected_54 = {
    original
    |> websocket.options_upgrade_options
    |> websocket.upgrade_options_to_ffi
  }
  let assert #(True, _, _) = #(actual_54 == expected_54, actual_54, expected_54)
  Nil
}

pub fn websocket_session_options_with_connect_options_updates_only_connection_options_test() -> Nil {
  let original = websocket.options()
  let connect_options =
    connection.options()
    |> connection.with_transport(transport: connection.Tcp)
  let updated =
    original
    |> websocket.with_connect_options(connect_options)

  let actual_55 = {
    updated
    |> websocket.options_connect_options
    |> connection.transport
  }
  let expected_55 = connection.Tcp
  let assert #(True, _, _) = #(actual_55 == expected_55, actual_55, expected_55)

  let actual_56 = {
    updated
    |> websocket.options_headers
  }
  let expected_56 = websocket.options_headers(original)
  let assert #(True, _, _) = #(actual_56 == expected_56, actual_56, expected_56)

  let actual_57 = {
    updated
    |> websocket.options_timeout
  }
  let expected_57 = websocket.options_timeout(original)
  let assert #(True, _, _) = #(actual_57 == expected_57, actual_57, expected_57)

  let actual_58 = {
    updated
    |> websocket.options_upgrade_options
    |> websocket.upgrade_options_to_ffi
  }
  let expected_58 = {
    original
    |> websocket.options_upgrade_options
    |> websocket.upgrade_options_to_ffi
  }
  let assert #(True, _, _) = #(actual_58 == expected_58, actual_58, expected_58)
  Nil
}

pub fn websocket_session_options_with_upgrade_options_updates_only_upgrade_options_test() -> Nil {
  let original = websocket.options()
  let upgrade_options =
    websocket.upgrade_options()
    |> websocket.with_compress(True)
  let updated =
    original
    |> websocket.with_upgrade_options(upgrade_options)

  let actual_59 = {
    updated
    |> websocket.options_upgrade_options
    |> websocket.upgrade_options_to_ffi
  }
  let expected_59 = [websocket.Compress(True)]
  let assert #(True, _, _) = #(actual_59 == expected_59, actual_59, expected_59)

  let actual_60 = {
    updated
    |> websocket.options_headers
  }
  let expected_60 = websocket.options_headers(original)
  let assert #(True, _, _) = #(actual_60 == expected_60, actual_60, expected_60)

  let actual_61 = {
    updated
    |> websocket.options_connect_options
    |> connection.protocols
  }
  let expected_61 = {
    original
    |> websocket.options_connect_options
    |> connection.protocols
  }
  let assert #(True, _, _) = #(actual_61 == expected_61, actual_61, expected_61)

  let actual_62 = {
    updated
    |> websocket.options_timeout
  }
  let expected_62 = websocket.options_timeout(original)
  let assert #(True, _, _) = #(actual_62 == expected_62, actual_62, expected_62)
  Nil
}

pub fn websocket_session_options_with_timeout_updates_only_timeout_test() -> Nil {
  let original = websocket.options()
  let updated =
    original
    |> websocket.with_timeout(connection.infinity())

  let actual_63 = {
    updated
    |> websocket.options_timeout
  }
  let expected_63 = connection.infinity()
  let assert #(True, _, _) = #(actual_63 == expected_63, actual_63, expected_63)

  let actual_64 = {
    updated
    |> websocket.options_headers
  }
  let expected_64 = websocket.options_headers(original)
  let assert #(True, _, _) = #(actual_64 == expected_64, actual_64, expected_64)

  let actual_65 = {
    updated
    |> websocket.options_connect_options
    |> connection.protocols
  }
  let expected_65 = {
    original
    |> websocket.options_connect_options
    |> connection.protocols
  }
  let assert #(True, _, _) = #(actual_65 == expected_65, actual_65, expected_65)

  let actual_66 = {
    updated
    |> websocket.options_upgrade_options
    |> websocket.upgrade_options_to_ffi
  }
  let expected_66 = {
    original
    |> websocket.options_upgrade_options
    |> websocket.upgrade_options_to_ffi
  }
  let assert #(True, _, _) = #(actual_66 == expected_66, actual_66, expected_66)
  Nil
}

pub fn websocket_session_cleanup_returns_callback_value_when_callback_and_cleanup_succeed_test() -> Nil {
  let actual_67 = websocket.with_socket_result(Ok("done"), Ok(Nil))
  let expected_67 = Ok("done")
  let assert #(True, _, _) = #(actual_67 == expected_67, actual_67, expected_67)
  Nil
}

pub fn websocket_session_cleanup_returns_close_frame_cleanup_errors_after_callback_success_test() -> Nil {
  let actual_68 =
    websocket.with_socket_result(
      Ok("done"),
      Error(error.StreamError("close frame failed")),
    )
  let expected_68 = Error(error.StreamError("close frame failed"))
  let assert #(True, _, _) = #(actual_68 == expected_68, actual_68, expected_68)
  Nil
}

pub fn websocket_session_cleanup_returns_connection_cleanup_errors_after_callback_success_test() -> Nil {
  let actual_69 =
    websocket.with_socket_result(
      Ok("done"),
      Error(error.ConnectionError("connection close failed")),
    )
  let expected_69 = Error(error.ConnectionError("connection close failed"))
  let assert #(True, _, _) = #(actual_69 == expected_69, actual_69, expected_69)
  Nil
}

pub fn websocket_session_cleanup_returns_the_callback_error_after_callback_failure_even_when_cleanup_fails_test() -> Nil {
  let actual_70 =
    websocket.with_socket_result(
      Error(error.InvalidMessage("callback failed")),
      Error(error.ConnectionError("connection close failed")),
    )
  let expected_70 = Error(error.InvalidMessage("callback failed"))
  let assert #(True, _, _) = #(actual_70 == expected_70, actual_70, expected_70)
  Nil
}

pub fn upgrade_routing_accepts_upgrade_messages_test() -> Nil {
  let actual_71 =
    websocket.await_upgrade_from(Ok(message.Upgrade(["websocket"], [])))
  let expected_71 = Ok(Nil)
  let assert #(True, _, _) = #(actual_71 == expected_71, actual_71, expected_71)
  Nil
}

pub fn upgrade_routing_accepts_upgrade_messages_with_headers_test() -> Nil {
  let actual_72 =
    websocket.await_upgrade_from(
      Ok(message.Upgrade(["websocket"], [#("sec-websocket-protocol", "chat")])),
    )
  let expected_72 = Ok(Nil)
  let assert #(True, _, _) = #(actual_72 == expected_72, actual_72, expected_72)
  Nil
}

pub fn upgrade_routing_rejects_websocket_frames_while_awaiting_upgrade_test() -> Nil {
  let actual_73 =
    websocket.await_upgrade_from(Ok(message.WebSocket(message.Text("oops"))))
  let expected_73 =
    Error(error.InvalidMessage(
      "websocket.await_upgrade: expected Upgrade message",
    ))
  let assert #(True, _, _) = #(actual_73 == expected_73, actual_73, expected_73)
  Nil
}

pub fn upgrade_routing_rejects_http_responses_while_awaiting_upgrade_test() -> Nil {
  let actual_74 =
    websocket.await_upgrade_from(Ok(message.Response(fin.Fin, 101, [])))
  let expected_74 =
    Error(error.InvalidMessage(
      "websocket.await_upgrade: expected Upgrade message",
    ))
  let assert #(True, _, _) = #(actual_74 == expected_74, actual_74, expected_74)
  Nil
}

pub fn upgrade_routing_propagates_timeout_while_awaiting_upgrade_test() -> Nil {
  let actual_75 = websocket.await_upgrade_from(Error(error.Timeout))
  let expected_75 = Error(error.Timeout)
  let assert #(True, _, _) = #(actual_75 == expected_75, actual_75, expected_75)
  Nil
}

pub fn upgrade_routing_rejects_http_2_before_calling_ffi_test() -> Nil {
  let actual_76 =
    websocket.upgrade_with_protocol(
      invalid_connection(),
      connection.Http2,
      "/ws",
      [],
    )
  let expected_76 =
    Error(error.UnsupportedFeature("WebSocket upgrade requires HTTP/1.1"))
  let assert #(True, _, _) = #(actual_76 == expected_76, actual_76, expected_76)
  Nil
}

pub fn upgrade_routing_surfaces_ffi_errors_from_upgrade_test() -> Nil {
  // Gun does not support WebSocket over HTTP/2 (RFC 8441). That
  // limitation is documented in src/gluegun/websocket.gleam and the echo
  // example. This deterministic test does not create an HTTP/2 connection; it
  // verifies that errors raised by gun:ws_upgrade are surfaced as Result errors
  // rather than panicking or producing a misleading success.
  let actual_77 = websocket.upgrade(invalid_connection(), "/ws", [])
  let expected_77 = Error(error.ErlangError("Error(FunctionClause)"))
  let assert #(True, _, _) = #(actual_77 == expected_77, actual_77, expected_77)
  Nil
}

pub fn upgrade_injection_guards_rejects_a_crlf_split_upgrade_path_test() -> Nil {
  let actual_78 =
    websocket.upgrade(
      current_connection(),
      "/ws HTTP/1.1\r\nX-Injected: evil",
      [],
    )
  let expected_78 = Error(error.InvalidOptions("Request(InvalidPath)"))
  let assert #(True, _, _) = #(actual_78 == expected_78, actual_78, expected_78)
  Nil
}

pub fn upgrade_injection_guards_rejects_a_literal_space_in_the_upgrade_path_test() -> Nil {
  let actual_79 = websocket.upgrade(current_connection(), "/ws HTTP/1.1", [])
  let expected_79 = Error(error.InvalidOptions("Request(InvalidPath)"))
  let assert #(True, _, _) = #(actual_79 == expected_79, actual_79, expected_79)
  Nil
}

pub fn upgrade_injection_guards_rejects_an_empty_upgrade_path_test() -> Nil {
  let actual_80 = websocket.upgrade(current_connection(), "", [])
  let expected_80 = Error(error.InvalidOptions("Request(InvalidPath)"))
  let assert #(True, _, _) = #(actual_80 == expected_80, actual_80, expected_80)
  Nil
}

pub fn upgrade_injection_guards_rejects_a_crlf_injected_upgrade_header_value_test() -> Nil {
  let actual_81 =
    websocket.upgrade(current_connection(), "/ws", [
      #("X-Trace", "abc\r\nX-Injected: evil"),
    ])
  let expected_81 = Error(error.InvalidOptions("Request(InvalidHeaderValue)"))
  let assert #(True, _, _) = #(actual_81 == expected_81, actual_81, expected_81)
  Nil
}

pub fn upgrade_injection_guards_rejects_a_vertical_tab_byte_in_an_upgrade_header_value_test() -> Nil {
  let actual_82 =
    websocket.upgrade(current_connection(), "/ws", [
      #("X-Trace", "abc\u{000B}def"),
    ])
  let expected_82 = Error(error.InvalidOptions("Request(InvalidHeaderValue)"))
  let assert #(True, _, _) = #(actual_82 == expected_82, actual_82, expected_82)
  Nil
}

pub fn upgrade_injection_guards_rejects_an_invalid_upgrade_header_name_test() -> Nil {
  let actual_83 =
    websocket.upgrade(current_connection(), "/ws", [
      #("X-Trace: evil", "abc"),
    ])
  let expected_83 = Error(error.InvalidOptions("Request(InvalidHeaderName)"))
  let assert #(True, _, _) = #(actual_83 == expected_83, actual_83, expected_83)
  Nil
}

pub fn upgrade_injection_guards_rejects_a_caller_supplied_transfer_encoding_upgrade_header_test() -> Nil {
  let actual_84 =
    websocket.upgrade(current_connection(), "/ws", [
      #("Transfer-Encoding", "chunked"),
    ])
  let expected_84 =
    Error(error.InvalidOptions("Request(ForbiddenTransferEncodingHeader)"))
  let assert #(True, _, _) = #(actual_84 == expected_84, actual_84, expected_84)
  Nil
}

pub fn websocket_upgrade_options_encodes_default_options_to_an_empty_option_list_test() -> Nil {
  let actual_85 = {
    websocket.upgrade_options()
    |> websocket.upgrade_options_to_ffi
  }
  let expected_85 = []
  let assert #(True, _, _) = #(actual_85 == expected_85, actual_85, expected_85)
  Nil
}

pub fn websocket_upgrade_options_encodes_typed_gun_ws_opts_fields_test() -> Nil {
  let actual_86 = {
    websocket.upgrade_options()
    |> websocket.with_compress(True)
    |> websocket.with_silence_pings(True)
    |> websocket.with_flow(8)
    |> websocket.with_keepalive(timeout(30_000))
    |> websocket.with_closing_timeout(connection.infinity())
    |> websocket.upgrade_options_to_ffi
  }
  let expected_86 = [
    websocket.SilencePings(True),
    websocket.Keepalive(timeout(30_000)),
    websocket.Flow(8),
    websocket.Compress(True),
    websocket.ClosingTimeout(connection.infinity()),
  ]
  let assert #(True, _, _) = #(actual_86 == expected_86, actual_86, expected_86)
  Nil
}

pub fn websocket_upgrade_options_preserves_protocol_module_values_test() -> Nil {
  let actual_87 = {
    websocket.upgrade_options()
    |> websocket.with_default_protocol_module("my_ws_h")
    |> websocket.with_protocol_module("chat", "chat_ws_h")
    |> websocket.upgrade_options_to_ffi
  }
  let expected_87 = [
    websocket.Protocols([#("chat", "chat_ws_h")]),
    websocket.DefaultProtocol("my_ws_h"),
  ]
  let assert #(True, _, _) = #(actual_87 == expected_87, actual_87, expected_87)
  Nil
}

pub fn websocket_upgrade_options_preserves_reply_to_tunnel_and_handler_options_test() -> Nil {
  let reply_to = process.self()
  let tunnel = stream_ref()
  let handler_options = raw.handler_options(#(1, "two"))

  let actual_88 = {
    websocket.upgrade_options()
    |> raw.with_reply_to(reply_to)
    |> raw.with_tunnel(tunnel)
    |> raw.with_handler_options(handler_options)
    |> websocket.upgrade_options_to_ffi
  }
  let expected_88 = [
    websocket.UserOptions(handler_options),
    websocket.Tunnel(tunnel),
    websocket.ReplyTo(reply_to),
  ]
  let assert #(True, _, _) = #(actual_88 == expected_88, actual_88, expected_88)
  Nil
}

pub fn websocket_upgrade_options_normalizes_typed_options_before_calling_gun_test() -> Nil {
  let actual_89 = {
    websocket.upgrade_options()
    |> websocket.with_compress(True)
    |> websocket.with_silence_pings(False)
    |> websocket.with_flow(16)
    |> websocket.with_keepalive(timeout(45_000))
    |> websocket.with_closing_timeout(connection.infinity())
    |> websocket.upgrade_options_to_ffi
    |> capture_ws_upgrade_options
  }
  let expected_89 =
    Ok(
      captured_ws_options(
        compress: Some(True),
        silence_pings: Some(False),
        flow: Some(16),
        keepalive: Some("45000"),
        closing_timeout: Some("infinity"),
        default_protocol: None,
        protocols: [],
      ),
    )
  let assert #(True, _, _) = #(actual_89 == expected_89, actual_89, expected_89)
  Nil
}

pub fn websocket_upgrade_options_normalizes_protocol_modules_before_calling_gun_test() -> Nil {
  let actual_90 = {
    websocket.upgrade_options()
    |> websocket.with_default_protocol_module("gluegun_ws_test")
    |> websocket.with_protocol_module("chat", "gluegun_ws_test")
    |> websocket.upgrade_options_to_ffi
    |> capture_ws_upgrade_options
  }
  let expected_90 =
    Ok(
      captured_ws_options(
        compress: None,
        silence_pings: None,
        flow: None,
        keepalive: None,
        closing_timeout: None,
        default_protocol: Some("gluegun_ws_test"),
        protocols: [#("chat", "gluegun_ws_test")],
      ),
    )
  let assert #(True, _, _) = #(actual_90 == expected_90, actual_90, expected_90)
  Nil
}

pub fn websocket_upgrade_options_rejects_unknown_default_protocol_modules_before_calling_gun_test() -> Nil {
  let actual_91 = {
    websocket.upgrade_options()
    |> websocket.with_default_protocol_module("gluegun_nonexistent_ws_handler")
    |> websocket.upgrade_options_to_ffi
    |> capture_ws_upgrade_options
  }
  let expected_91 =
    Error(error.InvalidOptions(
      "Ws(UnknownModule(\"gluegun_nonexistent_ws_handler\"))",
    ))
  let assert #(True, _, _) = #(actual_91 == expected_91, actual_91, expected_91)
  Nil
}

pub fn websocket_upgrade_options_rejects_unknown_protocol_modules_before_calling_gun_test() -> Nil {
  let actual_92 = {
    websocket.upgrade_options()
    |> websocket.with_protocol_module(
      "chat",
      "gluegun_nonexistent_protocol_ws_handler",
    )
    |> websocket.upgrade_options_to_ffi
    |> capture_ws_upgrade_options
  }
  let expected_92 =
    Error(error.InvalidOptions(
      "Ws(UnknownModule(\"gluegun_nonexistent_protocol_ws_handler\"))",
    ))
  let assert #(True, _, _) = #(actual_92 == expected_92, actual_92, expected_92)
  Nil
}

pub fn websocket_upgrade_options_returns_invalidoptions_for_invalid_gun_ws_opts_test() -> Nil {
  let actual_93 = invalid_ws_upgrade_options_result()
  let expected_93 = Error(error.InvalidOptions("Ws(Compress)"))
  let assert #(True, _, _) = #(actual_93 == expected_93, actual_93, expected_93)
  Nil
}

// ── Helpers ──────────────────────────────────────────────────────────────────

fn timeout(milliseconds: Int) -> connection.Timeout {
  let assert Ok(timeout) = connection.milliseconds(milliseconds)
  timeout
}

/// Gun `ws_opts()` projected back into Gleam by `gluegun_ws_test`:
/// `#(compress, silence_pings, flow, keepalive, closing_timeout,
/// default_protocol, protocols)`. Timeouts are rendered as strings so
/// `infinity` and a millisecond count share one type.
type CapturedWebSocketOptions =
  #(
    Option(Bool),
    Option(Bool),
    Option(Int),
    Option(String),
    Option(String),
    Option(String),
    List(#(String, String)),
  )

/// A raw Gun WebSocket frame term, as carried inside a `{ws, Frame}` message.
type GunFrame

fn captured_ws_options(
  compress compress: Option(Bool),
  silence_pings silence_pings: Option(Bool),
  flow flow: Option(Int),
  keepalive keepalive: Option(String),
  closing_timeout closing_timeout: Option(String),
  default_protocol default_protocol: Option(String),
  protocols protocols: List(#(String, String)),
) -> CapturedWebSocketOptions {
  #(
    compress,
    silence_pings,
    flow,
    keepalive,
    closing_timeout,
    default_protocol,
    protocols,
  )
}

/// Decode a frame Gun was asked to send back into a typed message, so outbound
/// encoding can be asserted against the same `Frame` values callers pass in.
fn decode_captured_frame(
  captured: Result(message.GunMessage, error.GluegunError),
) -> Result(message.Message, error.GluegunError) {
  case captured {
    Ok(gun_message) -> safe_decode_message(gun_message)
    Error(error) -> Error(error)
  }
}

@external(erlang, "gluegun_ffi_test", "current_connection")
fn current_connection() -> internal.Connection

@external(erlang, "gluegun_ffi_test", "invalid_connection")
fn invalid_connection() -> internal.Connection

@external(erlang, "gluegun_ffi_test", "stream_ref")
fn stream_ref() -> internal.Stream

@external(erlang, "gluegun_ffi_test", "websocket_frame_message")
fn websocket_frame_message(frame: GunFrame) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "text_frame")
fn text_frame(data: BitArray) -> GunFrame

@external(erlang, "gluegun_ffi_test", "binary_frame")
fn binary_frame(data: BitArray) -> GunFrame

@external(erlang, "gluegun_ffi_test", "ping_frame")
fn ping_frame(data: BitArray) -> GunFrame

@external(erlang, "gluegun_ffi_test", "pong_frame")
fn pong_frame(data: BitArray) -> GunFrame

@external(erlang, "gluegun_ffi_test", "close_frame")
fn close_frame() -> GunFrame

@external(erlang, "gluegun_ffi_test", "close_with_reason_frame")
fn close_with_reason_frame(code: Int, reason: BitArray) -> GunFrame

@external(erlang, "gluegun_ffi", "safe_decode_message")
fn safe_decode_message(
  message: message.GunMessage,
) -> Result(message.Message, error.GluegunError)

@external(erlang, "gluegun_ws_test", "ws_close_message")
fn ws_close_message() -> message.GunMessage

@external(erlang, "gluegun_ws_test", "ws_close_with_reason_message")
fn ws_close_with_reason_message() -> message.GunMessage

@external(erlang, "gluegun_ws_test", "capture_ws_send_frame")
fn capture_ws_send_frame(
  frame: message.Frame,
) -> Result(message.GunMessage, error.GluegunError)

@external(erlang, "gluegun_ws_test", "capture_ws_send_frames")
fn capture_ws_send_frames() -> Result(List(#(String, BitArray)), Nil)

@external(erlang, "gluegun_ws_test", "capture_ws_upgrade_options")
fn capture_ws_upgrade_options(
  options: List(websocket.UpgradeOption),
) -> Result(CapturedWebSocketOptions, error.GluegunError)

@external(erlang, "gluegun_ws_test", "invalid_ws_send_frame_list_result")
fn invalid_ws_send_frame_list_result() -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ws_test", "invalid_ws_send_text_utf8_result")
fn invalid_ws_send_text_utf8_result() -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ws_test", "invalid_ws_upgrade_options_result")
fn invalid_ws_upgrade_options_result() -> Result(
  internal.Stream,
  error.GluegunError,
)
