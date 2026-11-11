import gleam/erlang/process
import gleam/http
import gluegun/client
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/internal
import gluegun/message
import gluegun/request
import gluegun/response

pub fn protocol_negotiation_encodes_protocol_preference_in_order_test() -> Nil {
  let actual_1 = {
    connection.options()
    |> connection.with_protocols([connection.Http2, connection.Http1])
    |> connection.options_to_ffi
  }
  let expected_1 = [
    connection.TransportOption(connection.Auto),
    connection.RetryOption(connection.default_retry_count()),
    connection.ConnectTimeoutOption(connection.default_timeout()),
    connection.ProtocolsOption([connection.Http2, connection.Http1]),
  ]
  let assert #(True, _, _) = #(actual_1 == expected_1, actual_1, expected_1)
  Nil
}

pub fn protocol_negotiation_decodes_await_up_protocol_results_test() -> Nil {
  let actual_2 = gun_protocol_result("http2")
  let expected_2 = Ok(connection.Http2)
  let assert #(True, _, _) = #(actual_2 == expected_2, actual_2, expected_2)
  Nil
}

pub fn protocol_negotiation_returns_decode_errors_for_invalid_await_up_protocols_test() -> Nil {
  let actual_3 = gun_protocol_result("spdy")
  let expected_3 = Error(error.DecodeError("Invalid protocol"))
  let assert #(True, _, _) = #(actual_3 == expected_3, actual_3, expected_3)
  Nil
}

pub fn http_helper_compatibility_collects_normal_http_responses_from_http_2_like_streams_test() -> Nil {
  let actual_4 =
    client.collect_messages([
      Ok(message.Response(fin.NoFin, 200, [#("content-type", "text/plain")])),
      Ok(message.Data(fin.NoFin, <<"hello ":utf8>>)),
      Ok(message.Data(fin.NoFin, <<"from ":utf8>>)),
      Ok(message.Data(fin.Fin, <<"http2":utf8>>)),
    ])
  let expected_4 =
    Ok(
      response.new(
        status: 200,
        headers: [#("content-type", "text/plain")],
        body: <<"hello from http2":utf8>>,
        trailers: [],
      ),
    )
  let assert #(True, _, _) = #(actual_4 == expected_4, actual_4, expected_4)
  Nil
}

pub fn http_helper_compatibility_uses_the_negotiated_http_2_response_path_test() -> Nil {
  let negotiated = gun_protocol_result("http2")
  let actual_5 = negotiated
  let expected_5 = Ok(connection.Http2)
  let assert #(True, _, _) = #(actual_5 == expected_5, actual_5, expected_5)

  let request_subject = process.new_subject()
  let message_subject = process.new_subject()
  let test_connection = invalid_connection()
  let test_stream = stream_ref()
  let expected_path = "/deterministic-http2"
  let expected_headers = [#("accept", "text/plain"), #("x-test", "http2")]

  process.send(
    message_subject,
    Ok(message.Response(fin.NoFin, 200, [#("content-type", "text/plain")])),
  )
  process.send(
    message_subject,
    Ok(message.Data(fin.Fin, <<"hello from deterministic get":utf8>>)),
  )

  let fake_request = fn(
    _connection: connection.Connection,
    method: http.Method,
    path: String,
    headers: List(request.Header),
    body: BitArray,
    _options: request.RequestOptions,
  ) -> Result(request.Stream, error.GluegunError) {
    process.send(request_subject, #(method, path, headers, body))
    Ok(test_stream)
  }
  let fake_await = fn(
    _connection: connection.Connection,
    stream: request.Stream,
    _timeout: connection.Timeout,
  ) -> Result(message.Message, error.GluegunError) {
    let actual_6 = stream
    let expected_6 = test_stream
    let assert #(True, _, _) = #(actual_6 == expected_6, actual_6, expected_6)

    case process.receive(message_subject, within: 0) {
      Ok(next) -> next
      Error(_) -> Error(error.Timeout)
    }
  }

  let actual = case negotiated {
    Ok(connection.Http2) ->
      client.get_with(
        test_connection,
        expected_path,
        expected_headers,
        timeout(10),
        fake_request,
        fake_await,
      )
    Ok(connection.Http1) ->
      Error(error.DecodeError("HTTP/2 was not negotiated"))
    Error(_) -> Error(error.DecodeError("HTTP/2 was not negotiated"))
  }

  let actual_7 = actual
  let expected_7 =
    Ok(
      response.new(
        status: 200,
        headers: [#("content-type", "text/plain")],
        body: <<"hello from deterministic get":utf8>>,
        trailers: [],
      ),
    )
  let assert #(True, _, _) = #(actual_7 == expected_7, actual_7, expected_7)
  let actual_8 = process.receive(request_subject, within: 0)
  let expected_8 = Ok(#(http.Get, expected_path, expected_headers, <<>>))
  let assert #(True, _, _) = #(actual_8 == expected_8, actual_8, expected_8)
  Nil
}

fn timeout(milliseconds: Int) -> connection.Timeout {
  let assert Ok(timeout) = connection.milliseconds(milliseconds)
  timeout
}

@external(erlang, "gluegun_ffi_test", "protocol_result")
fn gun_protocol_result(
  protocol: String,
) -> Result(connection.Protocol, error.GluegunError)

@external(erlang, "gluegun_ffi_test", "invalid_connection")
fn invalid_connection() -> internal.Connection

@external(erlang, "gluegun_ffi_test", "stream_ref")
fn stream_ref() -> internal.Stream
