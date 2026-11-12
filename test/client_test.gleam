import gleam/bit_array
import gleam/erlang/process
import gleam/http
import gleam/http/response as http_response
import gleam/option.{None, Some}
import gluegun/client
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/internal
import gluegun/message
import gluegun/response

pub fn total_deadline_reduces_the_injected_await_budget_test() -> Nil {
  let observed = process.new_subject()
  let request_fn = fn(_, _, _, _, _, _) { Ok(stream_ref()) }
  let await_fn = fn(_, _, wait) {
    process.send(observed, connection.deadline(wait))
    process.sleep(20)
    Ok(message.Inform(103, []))
  }
  let result =
    client.get_with(
      invalid_connection(),
      "/",
      [],
      timeout(70),
      request_fn,
      await_fn,
    )
  let assert True = result == Error(error.Timeout)
  let assert Ok(Some(first)) = process.receive(observed, within: 0)
  let assert Ok(Some(second)) = process.receive(observed, within: 0)
  // Reconstructed deadlines stay fixed instead of advancing with each chunk.
  let assert True = second <= first + 5
  Nil
}

pub fn infinite_collection_budget_stays_unlimited_test() -> Nil {
  let request_fn = fn(_, _, _, _, _, _) { Ok(stream_ref()) }
  let await_fn = fn(_, _, wait) {
    let assert True = connection.deadline(wait) == None
    Ok(message.Response(fin.Fin, 204, []))
  }
  let assert Ok(res) =
    client.get_with(
      invalid_connection(),
      "/",
      [],
      connection.infinity(),
      request_fn,
      await_fn,
    )
  let assert True = response.status(res) == 204
  Nil
}

pub fn zero_collection_budget_does_not_receive_queued_messages_test() -> Nil {
  let request_fn = fn(_, _, _, _, _, _) { Ok(stream_ref()) }
  let await_fn = fn(_, _, _) { panic as "expired budget reached await" }
  let assert True =
    client.get_with(
      invalid_connection(),
      "/",
      [],
      timeout(0),
      request_fn,
      await_fn,
    )
    == Error(error.Timeout)
  Nil
}

pub fn request_builder_sets_request_fields_test() -> Nil {
  let actual_1 = {
    client.new(http.Get, "/")
    |> client.with_header("accept", "application/json")
    |> client.with_body(<<"":utf8>>)
    |> client.with_timeout(timeout(1000))
    |> client.inspect_request
  }
  let expected_1 =
    client.RequestFields(
      method: http.Get,
      path: "/",
      headers: [#("accept", "application/json")],
      body: <<"":utf8>>,
      timeout: timeout(1000),
    )
  let assert #(True, _, _) = #(actual_1 == expected_1, actual_1, expected_1)
  Nil
}

pub fn request_builder_exposes_request_options_helper_name_test() -> Nil {
  let actual_2 = compile_request_options_helper(False)
  let expected_2 = Nil
  let assert #(True, _, _) = #(actual_2 == expected_2, actual_2, expected_2)
  Nil
}

pub fn request_builder_add_headers_appends_request_headers_test() -> Nil {
  let actual_3 = {
    client.new(http.Get, "/")
    |> client.add_headers([#("accept", "application/json")])
    |> client.add_headers([#("x-request-id", "abc")])
    |> client.inspect_request
  }
  let expected_3 =
    client.RequestFields(
      method: http.Get,
      path: "/",
      headers: [
        #("accept", "application/json"),
        #("x-request-id", "abc"),
      ],
      body: <<>>,
      timeout: connection.default_timeout(),
    )
  let assert #(True, _, _) = #(actual_3 == expected_3, actual_3, expected_3)
  Nil
}

pub fn request_builder_with_headers_replaces_request_headers_test() -> Nil {
  let actual_4 = {
    client.new(http.Get, "/")
    |> client.add_headers([#("accept", "application/json")])
    |> client.with_headers([#("x-request-id", "abc")])
    |> client.inspect_request
  }
  let expected_4 =
    client.RequestFields(
      method: http.Get,
      path: "/",
      headers: [#("x-request-id", "abc")],
      body: <<>>,
      timeout: connection.default_timeout(),
    )
  let assert #(True, _, _) = #(actual_4 == expected_4, actual_4, expected_4)
  Nil
}

pub fn response_collection_collects_a_single_final_body_test() -> Nil {
  let actual_5 =
    client.collect_messages([
      Ok(message.Response(fin.NoFin, 200, [#("content-type", "text/plain")])),
      Ok(message.Data(fin.Fin, <<"hello":utf8>>)),
    ])
  let expected_5 =
    Ok(
      response.new(
        status: 200,
        headers: [#("content-type", "text/plain")],
        body: <<"hello":utf8>>,
        trailers: [],
      ),
    )
  let assert #(True, _, _) = #(actual_5 == expected_5, actual_5, expected_5)
  Nil
}

pub fn response_collection_collects_multiple_data_chunks_in_order_test() -> Nil {
  let assert Ok(collected_response) =
    client.collect_messages([
      Ok(message.Response(fin.NoFin, 200, [])),
      Ok(message.Data(fin.NoFin, <<"chunk-1|":utf8>>)),
      Ok(message.Data(fin.NoFin, <<"chunk-2|":utf8>>)),
      Ok(message.Data(fin.NoFin, <<"chunk-3|":utf8>>)),
      Ok(message.Data(fin.NoFin, <<"chunk-4|":utf8>>)),
      Ok(message.Data(fin.Fin, <<"chunk-5":utf8>>)),
    ])

  let actual_6 = {
    collected_response
    |> response.body
  }
  let expected_6 = <<"chunk-1|chunk-2|chunk-3|chunk-4|chunk-5":utf8>>
  let assert #(True, _, _) = #(actual_6 == expected_6, actual_6, expected_6)
  Nil
}

pub fn response_collection_preserves_trailers_test() -> Nil {
  let assert Ok(collected_response) =
    client.collect_messages([
      Ok(message.Response(fin.NoFin, 200, [])),
      Ok(message.Data(fin.NoFin, <<"hello":utf8>>)),
      Ok(message.Trailers([#("expires", "soon")])),
    ])

  let actual_7 = {
    collected_response
    |> response.trailers
  }
  let expected_7 = [#("expires", "soon")]
  let assert #(True, _, _) = #(actual_7 == expected_7, actual_7, expected_7)
  Nil
}

pub fn response_collection_preserves_informational_responses_test() -> Nil {
  let assert Ok(collected_response) =
    client.collect_messages([
      Ok(message.Inform(103, [#("link", "</style.css>; rel=preload")])),
      Ok(message.Response(fin.Fin, 204, [#("server", "gun")])),
    ])

  let actual_8 = {
    collected_response
    |> response.informational
  }
  let expected_8 = [
    http_response.Response(
      status: 103,
      headers: [#("link", "</style.css>; rel=preload")],
      body: Nil,
    ),
  ]
  let assert #(True, _, _) = #(actual_8 == expected_8, actual_8, expected_8)
  Nil
}

pub fn response_collection_exposes_standard_binary_response_and_metadata_test() -> Nil {
  let headers = [
    #("content-type", "application/octet-stream"),
    #("set-cookie", "a=1"),
    #("set-cookie", "b=2"),
  ]
  let trailers = [#("x-checksum", "first"), #("x-checksum", "second")]
  let assert Ok(collected) =
    client.collect_messages([
      Ok(message.Inform(100, [])),
      Ok(message.Inform(103, [#("link", "</style.css>; rel=preload")])),
      Ok(message.Response(fin.NoFin, 200, headers)),
      Ok(message.Data(fin.NoFin, <<0, 255>>)),
      Ok(message.Trailers(trailers)),
    ])

  let assert True =
    collected.response
    == http_response.Response(status: 200, headers: headers, body: <<0, 255>>)
  let assert True =
    http_response.get_header(collected.response, "content-type")
    == Ok("application/octet-stream")
  let assert True = collected.trailers == trailers
  let assert True =
    collected.informational
    == [
      http_response.Response(status: 100, headers: [], body: Nil),
      http_response.Response(
        status: 103,
        headers: [#("link", "</style.css>; rel=preload")],
        body: Nil,
      ),
    ]
  let assert True =
    http_response.try_map(collected.response, bit_array.to_string) == Error(Nil)
  Nil
}

pub fn standard_response_body_transformation_preserves_collected_metadata_test() -> Nil {
  let assert Ok(collected) =
    client.collect_messages([
      Ok(message.Inform(103, [#("link", "</style.css>; rel=preload")])),
      Ok(message.Response(fin.NoFin, 200, [#("content-type", "text/plain")])),
      Ok(message.Data(fin.NoFin, <<"hello":utf8>>)),
      Ok(message.Trailers([#("x-checksum", "abc")])),
    ])
  let assert Ok(decoded) =
    http_response.try_map(collected.response, bit_array.to_string)
  let updated = response.Response(..collected, response: decoded)

  let assert True = updated.response.body == "hello"
  let assert True = updated.response.status == collected.response.status
  let assert True = updated.response.headers == collected.response.headers
  let assert True = updated.trailers == collected.trailers
  let assert True = updated.informational == collected.informational
  Nil
}

pub fn invalid_message_handling_rejects_informational_responses_after_the_final_response_test() -> Nil {
  let actual_9 =
    client.collect_messages([
      Ok(message.Response(fin.NoFin, 200, [])),
      Ok(message.Inform(103, [])),
    ])
  let expected_9 =
    Error(error.InvalidMessage(
      "HTTP helper received informational response after final response",
    ))
  let assert #(True, _, _) = #(actual_9 == expected_9, actual_9, expected_9)
  Nil
}

pub fn invalid_message_handling_rejects_push_upgrade_and_websocket_messages_test() -> Nil {
  let stream = stream_ref()

  let actual_10 =
    client.collect_messages([
      Ok(message.Push(stream, http.Get, "/pushed", [])),
    ])
  let expected_10 =
    Error(error.InvalidMessage("HTTP helper received push message"))
  let assert #(True, _, _) = #(actual_10 == expected_10, actual_10, expected_10)

  let actual_11 =
    client.collect_messages([Ok(message.Upgrade(["websocket"], []))])
  let expected_11 =
    Error(error.InvalidMessage("HTTP helper received upgrade message"))
  let assert #(True, _, _) = #(actual_11 == expected_11, actual_11, expected_11)

  let actual_12 =
    client.collect_messages([Ok(message.WebSocket(message.Text("hello")))])
  let expected_12 =
    Error(error.InvalidMessage("HTTP helper received websocket message"))
  let assert #(True, _, _) = #(actual_12 == expected_12, actual_12, expected_12)
  Nil
}

pub fn invalid_message_handling_rejects_body_data_before_a_response_test() -> Nil {
  let actual_13 =
    client.collect_messages([Ok(message.Data(fin.Fin, <<"oops":utf8>>))])
  let expected_13 =
    Error(error.InvalidMessage("HTTP helper received body before response"))
  let assert #(True, _, _) = #(actual_13 == expected_13, actual_13, expected_13)
  Nil
}

pub fn invalid_message_handling_rejects_duplicate_final_responses_test() -> Nil {
  let actual_14 =
    client.collect_messages([
      Ok(message.Response(fin.NoFin, 200, [])),
      Ok(message.Response(fin.Fin, 204, [])),
    ])
  let expected_14 =
    Error(error.InvalidMessage("HTTP helper received duplicate response"))
  let assert #(True, _, _) = #(actual_14 == expected_14, actual_14, expected_14)
  Nil
}

pub fn invalid_message_handling_rejects_trailers_before_a_response_test() -> Nil {
  let actual_15 =
    client.collect_messages([Ok(message.Trailers([#("expires", "soon")]))])
  let expected_15 =
    Error(error.InvalidMessage("HTTP helper received trailers before response"))
  let assert #(True, _, _) = #(actual_15 == expected_15, actual_15, expected_15)
  Nil
}

pub fn invalid_message_handling_propagates_timeout_and_connection_down_errors_test() -> Nil {
  let actual_16 = client.collect_messages([Error(error.Timeout)])
  let expected_16 = Error(error.Timeout)
  let assert #(True, _, _) = #(actual_16 == expected_16, actual_16, expected_16)

  let actual_17 =
    client.collect_messages([Error(error.ConnectionDown("closed"))])
  let expected_17 = Error(error.ConnectionDown("closed"))
  let assert #(True, _, _) = #(actual_17 == expected_17, actual_17, expected_17)
  Nil
}

pub fn response_body_text_decodes_utf_8_bodies_test() -> Nil {
  let actual_18 = {
    response.new(status: 200, headers: [], body: <<"héllo":utf8>>, trailers: [])
    |> response.body_text
  }
  let expected_18 = Ok("héllo")
  let assert #(True, _, _) = #(actual_18 == expected_18, actual_18, expected_18)
  Nil
}

pub fn response_body_text_rejects_invalid_utf_8_bodies_test() -> Nil {
  let actual_19 = {
    response.new(status: 200, headers: [], body: <<255>>, trailers: [])
    |> response.body_text
  }
  let expected_19 = Error(error.DecodeError("Response body is not valid UTF-8"))
  let assert #(True, _, _) = #(actual_19 == expected_19, actual_19, expected_19)
  Nil
}

pub fn failed_stream_cleanup_cancels_on_timeout_before_headers_test() -> Nil {
  let actual_20 = failure_cleanup([Error(error.Timeout)], error.Timeout, False)
  let expected_20 = Ok(Nil)
  let assert #(True, _, _) = #(actual_20 == expected_20, actual_20, expected_20)
  Nil
}

pub fn failed_stream_cleanup_cancels_on_timeout_after_partial_body_test() -> Nil {
  let actual_21 =
    failure_cleanup(
      [
        Ok(message.Response(fin.NoFin, 200, [])),
        Ok(message.Data(fin.NoFin, <<"partial">>)),
        Error(error.Timeout),
      ],
      error.Timeout,
      False,
    )
  let expected_21 = Ok(Nil)
  let assert #(True, _, _) = #(actual_21 == expected_21, actual_21, expected_21)
  Nil
}

pub fn failed_stream_cleanup_cancels_on_invalid_collection_messages_test() -> Nil {
  let actual_22 =
    failure_cleanup(
      [Ok(message.Data(fin.Fin, <<"unexpected">>))],
      error.InvalidMessage("HTTP helper received body before response"),
      False,
    )
  let expected_22 = Ok(Nil)
  let assert #(True, _, _) = #(actual_22 == expected_22, actual_22, expected_22)
  Nil
}

pub fn failed_stream_cleanup_cancels_on_receive_and_decode_failures_test() -> Nil {
  let actual_23 =
    failure_cleanup(
      [Error(error.StreamError("reset"))],
      error.StreamError("reset"),
      False,
    )
  let expected_23 = Ok(Nil)
  let assert #(True, _, _) = #(actual_23 == expected_23, actual_23, expected_23)
  let actual_24 =
    failure_cleanup(
      [Error(error.DecodeError("malformed"))],
      error.DecodeError("malformed"),
      False,
    )
  let expected_24 = Ok(Nil)
  let assert #(True, _, _) = #(actual_24 == expected_24, actual_24, expected_24)
  let actual_25 =
    failure_cleanup(
      [Error(error.ConnectionDown("closed"))],
      error.ConnectionDown("closed"),
      False,
    )
  let expected_25 = Ok(Nil)
  let assert #(True, _, _) = #(actual_25 == expected_25, actual_25, expected_25)
  Nil
}

pub fn failed_stream_cleanup_drains_even_if_cancel_fails_and_keeps_original_error_test() -> Nil {
  let actual_26 = failure_cleanup([Error(error.Timeout)], error.Timeout, True)
  let expected_26 = Ok(Nil)
  let assert #(True, _, _) = #(actual_26 == expected_26, actual_26, expected_26)
  Nil
}

pub fn failed_stream_cleanup_does_not_cancel_successful_or_rejected_requests_test() -> Nil {
  let actual_27 = no_cleanup(False)
  let expected_27 = Ok(Nil)
  let assert #(True, _, _) = #(actual_27 == expected_27, actual_27, expected_27)
  let actual_28 = no_cleanup(True)
  let expected_28 = Ok(Nil)
  let assert #(True, _, _) = #(actual_28 == expected_28, actual_28, expected_28)
  Nil
}

pub fn failed_stream_cleanup_defines_the_late_message_drain_race_test() -> Nil {
  let actual_29 = late_after_drain()
  let expected_29 = Ok(Nil)
  let assert #(True, _, _) = #(actual_29 == expected_29, actual_29, expected_29)
  Nil
}

pub fn rejected_push_before_headers_cancels_the_promised_stream_test() -> Nil {
  let assert Ok(Nil) = push_cleanup(False)
  Nil
}

pub fn rejected_push_during_body_cancels_the_promised_stream_test() -> Nil {
  let assert Ok(Nil) = push_cleanup(True)
  Nil
}

pub fn malformed_push_cancels_the_promised_stream_and_keeps_decode_error_test() -> Nil {
  let assert Ok(Nil) = malformed_push_cleanup()
  Nil
}

pub fn http2_rejected_push_before_headers_preserves_concurrent_request_test() -> Nil {
  let assert Ok(Nil) = http2_push_cleanup("headers")
  Nil
}

pub fn http2_rejected_push_during_body_preserves_concurrent_request_test() -> Nil {
  let assert Ok(Nil) = http2_push_cleanup("body")
  Nil
}

pub fn http2_queued_push_cleanup_preserves_concurrent_request_test() -> Nil {
  let assert Ok(Nil) = http2_push_cleanup("cleanup")
  Nil
}

pub fn failed_stream_cleanup_cancels_delayed_headers_and_preserves_shared_requests_test() -> Nil {
  let actual_30 = delayed_response(False)
  let expected_30 = Ok(Nil)
  let assert #(True, _, _) = #(actual_30 == expected_30, actual_30, expected_30)
  Nil
}

pub fn failed_stream_cleanup_cancels_delayed_body_and_preserves_shared_requests_test() -> Nil {
  let actual_31 = delayed_response(True)
  let expected_31 = Ok(Nil)
  let assert #(True, _, _) = #(actual_31 == expected_31, actual_31, expected_31)
  Nil
}

pub fn failed_stream_cleanup_cleans_invalid_messages_on_a_shared_local_connection_test() -> Nil {
  let actual_32 = local_failure(False)
  let expected_32 = Ok(Nil)
  let assert #(True, _, _) = #(actual_32 == expected_32, actual_32, expected_32)
  Nil
}

pub fn failed_stream_cleanup_cleans_receive_failures_on_a_shared_local_connection_test() -> Nil {
  let actual_33 = local_failure(True)
  let expected_33 = Ok(Nil)
  let assert #(True, _, _) = #(actual_33 == expected_33, actual_33, expected_33)
  Nil
}

fn timeout(milliseconds: Int) -> connection.Timeout {
  let assert Ok(timeout) = connection.milliseconds(milliseconds)
  timeout
}

fn compile_request_options_helper(should_run: Bool) -> Nil {
  case should_run {
    True -> {
      let _ = client.options(invalid_connection(), "/", [], timeout(1000))
      Nil
    }
    False -> Nil
  }
}

@external(erlang, "gluegun_ffi_test", "stream_ref")
fn stream_ref() -> internal.Stream

@external(erlang, "gluegun_ffi_test", "invalid_connection")
fn invalid_connection() -> internal.Connection

@external(erlang, "gluegun_client_test", "failure_cleanup")
fn failure_cleanup(
  messages: List(Result(message.Message, error.GluegunError)),
  expected: error.GluegunError,
  invalid_connection: Bool,
) -> Result(Nil, String)

@external(erlang, "gluegun_client_test", "no_cleanup")
fn no_cleanup(send_failure: Bool) -> Result(Nil, String)

@external(erlang, "gluegun_client_test", "late_after_drain")
fn late_after_drain() -> Result(Nil, String)

@external(erlang, "gluegun_client_test", "delayed_response")
fn delayed_response(body_delay: Bool) -> Result(Nil, String)

@external(erlang, "gluegun_client_test", "local_failure")
fn local_failure(receive_failure: Bool) -> Result(Nil, String)

@external(erlang, "gluegun_client_test", "push_cleanup")
fn push_cleanup(body_started: Bool) -> Result(Nil, String)

@external(erlang, "gluegun_client_test", "malformed_push_cleanup")
fn malformed_push_cleanup() -> Result(Nil, String)

@external(erlang, "gluegun_http2_test", "http2_push_cleanup")
fn http2_push_cleanup(mode: String) -> Result(Nil, String)
