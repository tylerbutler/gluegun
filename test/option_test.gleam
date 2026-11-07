import gleam/option.{None, Some}
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/internal
import gluegun/message
import gluegun/request
import gluegun/response

pub fn connection_options_uses_default_connect_options_test() -> Nil {
  let options = connection.options()

  let actual_1 = {
    options
    |> connection.transport
  }
  let expected_1 = connection.Auto
  let assert #(True, _, _) = #(actual_1 == expected_1, actual_1, expected_1)

  let actual_2 = {
    options
    |> connection.protocols
  }
  let expected_2 = None
  let assert #(True, _, _) = #(actual_2 == expected_2, actual_2, expected_2)
  Nil
}

pub fn connection_options_exposes_connection_option_inspectors_test() -> Nil {
  let actual_3 = {
    connection.options()
    |> connection.transport
  }
  let expected_3 = connection.Auto
  let assert #(True, _, _) = #(actual_3 == expected_3, actual_3, expected_3)
  Nil
}

pub fn connection_options_preserves_protocol_ordering_test() -> Nil {
  let actual_4 = {
    connection.options()
    |> connection.with_protocols([connection.Http2, connection.Http1])
    |> connection.protocols
  }
  let expected_4 = Some([connection.Http2, connection.Http1])
  let assert #(True, _, _) = #(actual_4 == expected_4, actual_4, expected_4)
  Nil
}

pub fn request_options_and_methods_with_headers_replaces_request_headers_test() -> Nil {
  let actual_5 = {
    request.options()
    |> request.add_headers([#("accept", "application/json")])
    |> request.with_headers([#("x-request-id", "abc")])
    |> request.headers_option
  }
  let expected_5 = [#("x-request-id", "abc")]
  let assert #(True, _, _) = #(actual_5 == expected_5, actual_5, expected_5)
  Nil
}

pub fn request_options_and_methods_add_headers_appends_request_headers_test() -> Nil {
  let actual_6 = {
    request.options()
    |> request.add_headers([#("accept", "application/json")])
    |> request.add_headers([#("x-request-id", "abc")])
    |> request.headers_option
  }
  let expected_6 = [
    #("accept", "application/json"),
    #("x-request-id", "abc"),
  ]
  let assert #(True, _, _) = #(actual_6 == expected_6, actual_6, expected_6)
  Nil
}

pub fn request_options_and_methods_converts_request_methods_to_strings_test() -> Nil {
  let actual_7 = request.method_to_string(request.Get)
  let expected_7 = "GET"
  let assert #(True, _, _) = #(actual_7 == expected_7, actual_7, expected_7)

  let actual_8 = request.method_to_string(request.Post)
  let expected_8 = "POST"
  let assert #(True, _, _) = #(actual_8 == expected_8, actual_8, expected_8)

  let actual_9 = request.method_to_string(request.Head)
  let expected_9 = "HEAD"
  let assert #(True, _, _) = #(actual_9 == expected_9, actual_9, expected_9)

  let actual_10 = request.method_to_string(request.Put)
  let expected_10 = "PUT"
  let assert #(True, _, _) = #(actual_10 == expected_10, actual_10, expected_10)

  let actual_11 = request.method_to_string(request.Patch)
  let expected_11 = "PATCH"
  let assert #(True, _, _) = #(actual_11 == expected_11, actual_11, expected_11)

  let actual_12 = request.method_to_string(request.Delete)
  let expected_12 = "DELETE"
  let assert #(True, _, _) = #(actual_12 == expected_12, actual_12, expected_12)

  let actual_13 = request.method_to_string(request.Options)
  let expected_13 = "OPTIONS"
  let assert #(True, _, _) = #(actual_13 == expected_13, actual_13, expected_13)

  let actual_14 = request.method_to_string(request.Trace)
  let expected_14 = "TRACE"
  let assert #(True, _, _) = #(actual_14 == expected_14, actual_14, expected_14)

  let actual_15 = request.method_to_string(request.Connect)
  let expected_15 = "CONNECT"
  let assert #(True, _, _) = #(actual_15 == expected_15, actual_15, expected_15)

  let actual_16 = request.method_to_string(request.Custom("PROPFIND"))
  let expected_16 = "PROPFIND"
  let assert #(True, _, _) = #(actual_16 == expected_16, actual_16, expected_16)
  Nil
}

pub fn request_options_and_methods_normalizes_request_header_names_test() -> Nil {
  let actual_17 = {
    [#("Content-Type", "text/plain"), #("X-Request-ID", "ABC123")]
    |> request.normalize_headers
  }
  let expected_17 = [
    #("content-type", "text/plain"),
    #("x-request-id", "ABC123"),
  ]
  let assert #(True, _, _) = #(actual_17 == expected_17, actual_17, expected_17)
  Nil
}

pub fn responses_and_messages_constructs_responses_test() -> Nil {
  let constructed_response =
    response.new(
      status: 200,
      headers: [#("content-type", "text/plain")],
      body: <<"hello":utf8>>,
      trailers: [#("expires", "soon")],
    )
    |> response.with_informational(informational: [
      response.Informational(status: 103, headers: [#("server", "gun")]),
    ])

  let actual_18 = {
    constructed_response
    |> response.status
  }
  let expected_18 = 200
  let assert #(True, _, _) = #(actual_18 == expected_18, actual_18, expected_18)

  let actual_19 = {
    constructed_response
    |> response.headers
  }
  let expected_19 = [#("content-type", "text/plain")]
  let assert #(True, _, _) = #(actual_19 == expected_19, actual_19, expected_19)

  let actual_20 = {
    constructed_response
    |> response.body
  }
  let expected_20 = <<"hello":utf8>>
  let assert #(True, _, _) = #(actual_20 == expected_20, actual_20, expected_20)

  let actual_21 = {
    constructed_response
    |> response.trailers
  }
  let expected_21 = [#("expires", "soon")]
  let assert #(True, _, _) = #(actual_21 == expected_21, actual_21, expected_21)

  let actual_22 = {
    constructed_response
    |> response.informational
  }
  let expected_22 = [
    response.Informational(status: 103, headers: [#("server", "gun")]),
  ]
  let assert #(True, _, _) = #(actual_22 == expected_22, actual_22, expected_22)
  Nil
}

pub fn responses_and_messages_constructs_messages_test() -> Nil {
  let constructed = message.Response(fin.NoFin, 204, [#("server", "gun")])
  let assert message.Response(fin.NoFin, 204, [#("server", "gun")]) =
    constructed
  Nil
}

pub fn responses_and_messages_decodes_response_messages_test() -> Nil {
  let actual_23 = {
    response_message(fin.NoFin, 201, [#("Content-Type", "text/plain")])
    |> safe_decode_message
  }
  let expected_23 =
    Ok(message.Response(fin.NoFin, 201, [#("content-type", "text/plain")]))
  let assert #(True, _, _) = #(actual_23 == expected_23, actual_23, expected_23)
  Nil
}

pub fn responses_and_messages_decodes_data_messages_test() -> Nil {
  let actual_24 = {
    data_message(fin.Fin, <<"ok":utf8>>)
    |> safe_decode_message
  }
  let expected_24 = Ok(message.Data(fin.Fin, <<"ok":utf8>>))
  let assert #(True, _, _) = #(actual_24 == expected_24, actual_24, expected_24)
  Nil
}

pub fn responses_and_messages_decodes_informational_messages_test() -> Nil {
  let actual_25 = {
    inform_message(102, [#("Server", "gun")])
    |> safe_decode_message
  }
  let expected_25 = Ok(message.Inform(102, [#("server", "gun")]))
  let assert #(True, _, _) = #(actual_25 == expected_25, actual_25, expected_25)
  Nil
}

pub fn responses_and_messages_matches_unsupported_feature_errors_test() -> Nil {
  let unsupported =
    error.UnsupportedFeature("WebSocket upgrade requires HTTP/1.1")
  let error.UnsupportedFeature(reason) = unsupported

  let actual_26 = reason
  let expected_26 = "WebSocket upgrade requires HTTP/1.1"
  let assert #(True, _, _) = #(actual_26 == expected_26, actual_26, expected_26)
  Nil
}

pub fn responses_and_messages_decodes_trailer_messages_test() -> Nil {
  let actual_27 = {
    trailers_message([#("Expires", "soon")])
    |> safe_decode_message
  }
  let expected_27 = Ok(message.Trailers([#("expires", "soon")]))
  let assert #(True, _, _) = #(actual_27 == expected_27, actual_27, expected_27)
  Nil
}

pub fn responses_and_messages_decodes_upgrade_messages_test() -> Nil {
  let actual_28 = {
    upgrade_message(["websocket"], [#("Connection", "upgrade")])
    |> safe_decode_message
  }
  let expected_28 =
    Ok(message.Upgrade(["websocket"], [#("connection", "upgrade")]))
  let assert #(True, _, _) = #(actual_28 == expected_28, actual_28, expected_28)
  Nil
}

pub fn responses_and_messages_decodes_push_messages_test() -> Nil {
  let stream = stream_ref()

  let actual_29 = {
    push_message(stream, "POST", "/assets/app.css", [
      #("Accept", "text/css"),
    ])
    |> safe_decode_message
  }
  let expected_29 =
    Ok(
      message.Push(stream, request.Post, "/assets/app.css", [
        #("accept", "text/css"),
      ]),
    )
  let assert #(True, _, _) = #(actual_29 == expected_29, actual_29, expected_29)
  Nil
}

pub fn responses_and_messages_preserves_custom_push_method_case_test() -> Nil {
  let stream = stream_ref()

  let actual_30 = {
    push_message(stream, "PropFind", "/collection", [])
    |> safe_decode_message
  }
  let expected_30 =
    Ok(message.Push(stream, request.Custom("PropFind"), "/collection", []))
  let assert #(True, _, _) = #(actual_30 == expected_30, actual_30, expected_30)
  Nil
}

pub fn responses_and_messages_matches_known_push_methods_case_insensitively_test() -> Nil {
  let stream = stream_ref()

  let actual_31 = {
    push_message(stream, "get", "/", [])
    |> safe_decode_message
  }
  let expected_31 = Ok(message.Push(stream, request.Get, "/", []))
  let assert #(True, _, _) = #(actual_31 == expected_31, actual_31, expected_31)
  Nil
}

pub fn responses_and_messages_rejects_unknown_message_tags_test() -> Nil {
  let actual_32 = {
    unknown_message()
    |> safe_decode_message
  }
  let expected_32 = Error(error.InvalidMessage("Mystery(\"unknown\")"))
  let assert #(True, _, _) = #(actual_32 == expected_32, actual_32, expected_32)
  Nil
}

pub fn responses_and_messages_rejects_unknown_websocket_frame_tags_test() -> Nil {
  let actual_33 = {
    unknown_websocket_frame_message()
    |> safe_decode_message
  }
  let expected_33 = Error(error.InvalidMessage("Ws(Mystery(\"unknown\"))"))
  let assert #(True, _, _) = #(actual_33 == expected_33, actual_33, expected_33)
  Nil
}

pub fn responses_and_messages_decodes_websocket_messages_test() -> Nil {
  let actual_34 = {
    websocket_frame_message(text_frame(<<"hello":utf8>>))
    |> safe_decode_message
  }
  let expected_34 = Ok(message.WebSocket(message.Text("hello")))
  let assert #(True, _, _) = #(actual_34 == expected_34, actual_34, expected_34)
  Nil
}

pub fn responses_and_messages_message_decode_rejects_gun_await_3_style_terms_with_no_embedded_stream_test() -> Nil {
  let actual_35 = {
    response_message(fin.NoFin, 200, [])
    |> message.decode
  }
  let expected_35 = Error(error.DecodeError("Invalid Gun message"))
  let assert #(True, _, _) = #(actual_35 == expected_35, actual_35, expected_35)
  Nil
}

/// A raw Gun WebSocket frame term, as carried inside a `{ws, Frame}` message.
type GunFrame

@external(erlang, "gluegun_ffi_test", "stream_ref")
fn stream_ref() -> internal.Stream

@external(erlang, "gluegun_ffi", "safe_decode_message")
fn safe_decode_message(
  message: message.GunMessage,
) -> Result(message.Message, error.GluegunError)

@external(erlang, "gluegun_ffi_test", "inform_message")
fn inform_message(
  status: Int,
  headers: List(#(String, String)),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "response_message")
fn response_message(
  fin: fin.Fin,
  status: Int,
  headers: List(#(String, String)),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "data_message")
fn data_message(fin: fin.Fin, data: BitArray) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "trailers_message")
fn trailers_message(headers: List(#(String, String))) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "push_message")
fn push_message(
  stream: internal.Stream,
  method: String,
  uri: String,
  headers: List(#(String, String)),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "upgrade_message")
fn upgrade_message(
  protocols: List(String),
  headers: List(#(String, String)),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "websocket_frame_message")
fn websocket_frame_message(frame: GunFrame) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "unknown_message")
fn unknown_message() -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "unknown_websocket_frame_message")
fn unknown_websocket_frame_message() -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "text_frame")
fn text_frame(data: BitArray) -> GunFrame
