import gleam/http
import gluegun/error
import gluegun/fin
import gluegun/internal
import gluegun/request

pub fn request_ffi_shapes_normalizes_streaming_request_headers_test() -> Nil {
  let assert Ok(_stream) =
    request.start_stream(
      current_connection(),
      http.Post,
      "/upload",
      [#("Content-Type", "text/plain")],
      request.options()
        |> request.add_headers([#("X-Trace", "abc")]),
    )

  let actual_1 = capture_stream_headers()
  let expected_1 =
    Ok(
      #("POST", "/upload", [
        #("content-type", "text/plain"),
        #("x-trace", "abc"),
      ]),
    )
  let assert #(True, _, _) = #(actual_1 == expected_1, actual_1, expected_1)
  Nil
}

pub fn request_ffi_shapes_returns_an_opaque_stream_for_started_streams_test() -> Nil {
  let assert Ok(first) =
    request.start_stream(
      current_connection(),
      http.Post,
      "/upload",
      [],
      request.options(),
    )
  let assert Ok(second) =
    request.start_stream(
      current_connection(),
      http.Post,
      "/upload",
      [],
      request.options(),
    )
  let _ = capture_stream_headers()
  let _ = capture_stream_headers()

  let actual_2 = {
    first == second
  }
  let expected_2 = False
  let assert #(True, _, _) = #(actual_2 == expected_2, actual_2, expected_2)
  Nil
}

pub fn request_ffi_shapes_surfaces_request_errors_instead_of_stream_handles_test() -> Nil {
  let actual_3 =
    request.request(
      invalid_connection(),
      http.Post,
      "/upload",
      [],
      <<>>,
      request.options(),
    )
  let expected_3 = Error(error.ErlangError("Error(FunctionClause)"))
  let assert #(True, _, _) = #(actual_3 == expected_3, actual_3, expected_3)
  Nil
}

pub fn request_ffi_shapes_encodes_fin_values_for_streaming_data_test() -> Nil {
  let actual_4 = capture_data_fin(fin.Fin, <<"chunk":utf8>>)
  let expected_4 = Ok("fin")
  let assert #(True, _, _) = #(actual_4 == expected_4, actual_4, expected_4)

  let actual_5 = capture_data_fin(fin.NoFin, <<"chunk":utf8>>)
  let expected_5 = Ok("nofin")
  let assert #(True, _, _) = #(actual_5 == expected_5, actual_5, expected_5)
  Nil
}

pub fn request_injection_guards_rejects_a_crlf_split_request_path_test() -> Nil {
  let actual_6 =
    request.request(
      current_connection(),
      http.Get,
      "/upload HTTP/1.1\r\nX-Injected: evil",
      [],
      <<>>,
      request.options(),
    )
  let expected_6 = Error(error.InvalidOptions("Request(InvalidPath)"))
  let assert #(True, _, _) = #(actual_6 == expected_6, actual_6, expected_6)
  Nil
}

pub fn request_injection_guards_rejects_a_bare_nul_byte_in_the_request_path_test() -> Nil {
  let actual_7 =
    request.request(
      current_connection(),
      http.Get,
      "/upload\u{0000}.txt",
      [],
      <<>>,
      request.options(),
    )
  let expected_7 = Error(error.InvalidOptions("Request(InvalidPath)"))
  let assert #(True, _, _) = #(actual_7 == expected_7, actual_7, expected_7)
  Nil
}

pub fn request_injection_guards_rejects_a_literal_space_in_the_request_path_test() -> Nil {
  let actual_8 =
    request.request(
      current_connection(),
      http.Get,
      "/upload HTTP/1.1",
      [],
      <<>>,
      request.options(),
    )
  let expected_8 = Error(error.InvalidOptions("Request(InvalidPath)"))
  let assert #(True, _, _) = #(actual_8 == expected_8, actual_8, expected_8)
  Nil
}

pub fn request_injection_guards_rejects_an_empty_request_path_test() -> Nil {
  let actual_9 =
    request.request(
      current_connection(),
      http.Get,
      "",
      [],
      <<>>,
      request.options(),
    )
  let expected_9 = Error(error.InvalidOptions("Request(InvalidPath)"))
  let assert #(True, _, _) = #(actual_9 == expected_9, actual_9, expected_9)
  Nil
}

pub fn request_injection_guards_rejects_a_crlf_injected_header_value_test() -> Nil {
  let actual_10 =
    request.request(
      current_connection(),
      http.Post,
      "/upload",
      [#("X-Trace", "abc\r\nX-Injected: evil")],
      <<>>,
      request.options(),
    )
  let expected_10 = Error(error.InvalidOptions("Request(InvalidHeaderValue)"))
  let assert #(True, _, _) = #(actual_10 == expected_10, actual_10, expected_10)
  Nil
}

pub fn request_injection_guards_rejects_a_nul_byte_in_a_header_value_test() -> Nil {
  let actual_11 =
    request.request(
      current_connection(),
      http.Post,
      "/upload",
      [#("X-Trace", "abc\u{0000}def")],
      <<>>,
      request.options(),
    )
  let expected_11 = Error(error.InvalidOptions("Request(InvalidHeaderValue)"))
  let assert #(True, _, _) = #(actual_11 == expected_11, actual_11, expected_11)
  Nil
}

pub fn request_injection_guards_rejects_a_vertical_tab_byte_in_a_header_value_test() -> Nil {
  let actual_12 =
    request.request(
      current_connection(),
      http.Post,
      "/upload",
      [#("X-Trace", "abc\u{000B}def")],
      <<>>,
      request.options(),
    )
  let expected_12 = Error(error.InvalidOptions("Request(InvalidHeaderValue)"))
  let assert #(True, _, _) = #(actual_12 == expected_12, actual_12, expected_12)
  Nil
}

pub fn request_injection_guards_rejects_a_form_feed_byte_in_a_header_value_test() -> Nil {
  let actual_13 =
    request.request(
      current_connection(),
      http.Post,
      "/upload",
      [#("X-Trace", "abc\u{000C}def")],
      <<>>,
      request.options(),
    )
  let expected_13 = Error(error.InvalidOptions("Request(InvalidHeaderValue)"))
  let assert #(True, _, _) = #(actual_13 == expected_13, actual_13, expected_13)
  Nil
}

pub fn request_injection_guards_accepts_a_horizontal_tab_byte_in_a_header_value_test() -> Nil {
  let assert Ok(_stream) =
    request.start_stream(
      current_connection(),
      http.Post,
      "/upload",
      [#("X-Trace", "abc\tdef")],
      request.options(),
    )
  let actual_14 = capture_stream_headers()
  let expected_14 = Ok(#("POST", "/upload", [#("x-trace", "abc\tdef")]))
  let assert #(True, _, _) = #(actual_14 == expected_14, actual_14, expected_14)
  Nil
}

pub fn request_injection_guards_rejects_a_header_name_that_is_not_an_rfc_7230_token_test() -> Nil {
  let actual_15 =
    request.request(
      current_connection(),
      http.Post,
      "/upload",
      [#("X-Trace: evil", "abc")],
      <<>>,
      request.options(),
    )
  let expected_15 = Error(error.InvalidOptions("Request(InvalidHeaderName)"))
  let assert #(True, _, _) = #(actual_15 == expected_15, actual_15, expected_15)
  Nil
}

pub fn request_injection_guards_rejects_a_crlf_injected_header_name_test() -> Nil {
  let actual_16 =
    request.request(
      current_connection(),
      http.Post,
      "/upload",
      [#("X-Trace\r\nX-Injected", "evil")],
      <<>>,
      request.options(),
    )
  let expected_16 = Error(error.InvalidOptions("Request(InvalidHeaderName)"))
  let assert #(True, _, _) = #(actual_16 == expected_16, actual_16, expected_16)
  Nil
}

pub fn request_injection_guards_rejects_a_caller_supplied_transfer_encoding_header_test() -> Nil {
  let actual_17 =
    request.request(
      current_connection(),
      http.Post,
      "/upload",
      [#("Transfer-Encoding", "chunked")],
      <<>>,
      request.options(),
    )
  let expected_17 =
    Error(error.InvalidOptions("Request(ForbiddenTransferEncodingHeader)"))
  let assert #(True, _, _) = #(actual_17 == expected_17, actual_17, expected_17)
  Nil
}

pub fn request_injection_guards_rejects_duplicate_content_length_headers_test() -> Nil {
  let actual_18 =
    request.request(
      current_connection(),
      http.Post,
      "/upload",
      [#("Content-Length", "4"), #("Content-Length", "9999")],
      <<"data":utf8>>,
      request.options(),
    )
  let expected_18 =
    Error(error.InvalidOptions("Request(DuplicateContentLengthHeader)"))
  let assert #(True, _, _) = #(actual_18 == expected_18, actual_18, expected_18)
  Nil
}

pub fn request_injection_guards_rejects_a_non_numeric_content_length_header_test() -> Nil {
  let actual_19 =
    request.request(
      current_connection(),
      http.Post,
      "/upload",
      [#("Content-Length", "4 ; charset=evil")],
      <<"data":utf8>>,
      request.options(),
    )
  let expected_19 =
    Error(error.InvalidOptions("Request(InvalidContentLengthHeader)"))
  let assert #(True, _, _) = #(actual_19 == expected_19, actual_19, expected_19)
  Nil
}

pub fn request_injection_guards_rejects_a_crlf_split_custom_request_method_test() -> Nil {
  let actual_20 =
    request.request(
      current_connection(),
      http.Other("GET /other HTTP/1.1\r\nHost: evil"),
      "/upload",
      [],
      <<>>,
      request.options(),
    )
  let expected_20 = Error(error.InvalidOptions("Request(InvalidMethod)"))
  let assert #(True, _, _) = #(actual_20 == expected_20, actual_20, expected_20)
  Nil
}

pub fn request_injection_guards_applies_the_same_guards_to_start_stream_test() -> Nil {
  let actual_21 =
    request.start_stream(
      current_connection(),
      http.Post,
      "/upload",
      [#("X-Trace", "abc\r\nX-Injected: evil")],
      request.options(),
    )
  let expected_21 = Error(error.InvalidOptions("Request(InvalidHeaderValue)"))
  let assert #(True, _, _) = #(actual_21 == expected_21, actual_21, expected_21)
  Nil
}

pub fn stream_control_cancels_streams_on_an_open_connection_test() -> Nil {
  let actual_22 = request.cancel(current_connection(), stream_ref())
  let expected_22 = Ok(Nil)
  let assert #(True, _, _) = #(actual_22 == expected_22, actual_22, expected_22)
  Nil
}

pub fn stream_control_surfaces_cancel_errors_test() -> Nil {
  let actual_23 = request.cancel(invalid_connection(), stream_ref())
  let expected_23 = Error(error.StreamError("Error(FunctionClause)"))
  let assert #(True, _, _) = #(actual_23 == expected_23, actual_23, expected_23)
  Nil
}

pub fn stream_control_encodes_update_flow_increments_test() -> Nil {
  let actual_24 = capture_update_flow(1234)
  let expected_24 = Ok(1234)
  let assert #(True, _, _) = #(actual_24 == expected_24, actual_24, expected_24)
  Nil
}

pub fn stream_control_surfaces_update_flow_errors_test() -> Nil {
  let actual_25 = request.update_flow(invalid_connection(), stream_ref(), 1)
  let expected_25 = Error(error.StreamError("Error(FunctionClause)"))
  let assert #(True, _, _) = #(actual_25 == expected_25, actual_25, expected_25)
  Nil
}

pub fn stream_control_rejects_zero_update_flow_increments_test() -> Nil {
  let actual_26 = request.update_flow(current_connection(), stream_ref(), 0)
  let expected_26 =
    Error(error.InvalidOptions("flow-control increment must be positive"))
  let assert #(True, _, _) = #(actual_26 == expected_26, actual_26, expected_26)
  Nil
}

pub fn stream_control_rejects_negative_update_flow_increments_test() -> Nil {
  let actual_27 = request.update_flow(current_connection(), stream_ref(), -1)
  let expected_27 =
    Error(error.InvalidOptions("flow-control increment must be positive"))
  let assert #(True, _, _) = #(actual_27 == expected_27, actual_27, expected_27)
  Nil
}

@external(erlang, "gluegun_ffi_test", "current_connection")
fn current_connection() -> internal.Connection

@external(erlang, "gluegun_ffi_test", "invalid_connection")
fn invalid_connection() -> internal.Connection

@external(erlang, "gluegun_ffi_test", "stream_ref")
fn stream_ref() -> internal.Stream

@external(erlang, "gluegun_ffi_test", "capture_stream_headers")
fn capture_stream_headers() -> Result(
  #(String, String, List(#(String, String))),
  error.GluegunError,
)

@external(erlang, "gluegun_ffi_test", "capture_data_fin")
fn capture_data_fin(
  fin: fin.Fin,
  data: BitArray,
) -> Result(String, error.GluegunError)

@external(erlang, "gluegun_ffi_test", "capture_update_flow")
fn capture_update_flow(increment: Int) -> Result(Int, error.GluegunError)
