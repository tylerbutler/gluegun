import gluegun/connection
import gluegun/error
import gluegun/request

pub fn converts_finite_credit_for_both_request_entry_points_test() -> Nil {
  let assert Ok(options) = request.options() |> request.with_initial_flow(1)
  let actual_1 = {
    options
    |> request.with_headers([#("accept", "text/plain")])
    |> request.add_headers([#("x-test", "flow")])
    |> request.options_to_ffi
    |> capture_flow
  }
  let expected_1 = Ok(#("1", "1"))
  let assert #(True, _, _) = #(actual_1 == expected_1, actual_1, expected_1)
  let actual_2 = {
    request.options()
    |> request.options_to_ffi
    |> capture_flow
  }
  let expected_2 = Ok(#("infinity", "infinity"))
  let assert #(True, _, _) = #(actual_2 == expected_2, actual_2, expected_2)
  Nil
}

pub fn rejects_non_positive_initial_credit_test() -> Nil {
  let actual_3 = request.with_initial_flow(request.options(), 0)
  let expected_3 =
    Error(error.InvalidOptions("initial flow credit must be positive"))
  let assert #(True, _, _) = #(actual_3 == expected_3, actual_3, expected_3)
  let actual_4 = request.with_initial_flow(request.options(), -1)
  let expected_4 =
    Error(error.InvalidOptions("initial flow credit must be positive"))
  let assert #(True, _, _) = #(actual_4 == expected_4, actual_4, expected_4)
  Nil
}

pub fn rejects_negative_retry_counts_and_accepts_zero_test() -> Nil {
  let actual_5 = connection.retry_count(-1)
  let expected_5 =
    Error(error.InvalidOptions("retry count must be non-negative"))
  let assert #(True, _, _) = #(actual_5 == expected_5, actual_5, expected_5)
  let actual_6 = {
    configured(connection.Ipv4)
    |> connection.options_to_ffi
    |> project_setup
  }
  let expected_6 = #("inet", "0", "200", "200", "200", True)
  let assert #(True, _, _) = #(actual_6 == expected_6, actual_6, expected_6)
  Nil
}

pub fn preserves_setup_defaults_and_infinite_stage_timeouts_test() -> Nil {
  let actual_7 = {
    connection.options()
    |> connection.options_to_ffi
    |> project_setup
  }
  let expected_7 = #("default", "5", "5000", "infinity", "infinity", True)
  let assert #(True, _, _) = #(actual_7 == expected_7, actual_7, expected_7)
  let actual_8 = {
    connection.options()
    |> connection.with_address_family(connection.Ipv6)
    |> connection.with_domain_lookup_timeout(connection.infinity())
    |> connection.with_tls_handshake_timeout(timeout(0))
    |> connection.options_to_ffi
    |> project_setup
  }
  let expected_8 = #("inet6", "5", "5000", "infinity", "0", True)
  let assert #(True, _, _) = #(actual_8 == expected_8, actual_8, expected_8)
  Nil
}

pub fn rejects_invalid_raw_ffi_options_test() -> Nil {
  let actual_9 = invalid_options()
  let expected_9 = Ok(Nil)
  let assert #(True, _, _) = #(actual_9 == expected_9, actual_9, expected_9)
  Nil
}

pub fn pauses_one_large_http_chunk_until_credit_is_granted_test() -> Nil {
  let actual_10 = scenario("large", connection.Ipv4)
  let expected_10 = Ok(Nil)
  let assert #(True, _, _) = #(actual_10 == expected_10, actual_10, expected_10)
  Nil
}

pub fn pauses_many_small_http_chunks_until_credit_is_granted_test() -> Nil {
  let actual_11 = scenario("small", connection.Ipv4)
  let expected_11 = Ok(Nil)
  let assert #(True, _, _) = #(actual_11 == expected_11, actual_11, expected_11)
  Nil
}

pub fn rejects_oversized_content_length_before_body_transmission_test() -> Nil {
  let actual_12 = scenario("length", connection.Ipv4)
  let expected_12 = Ok(Nil)
  let assert #(True, _, _) = #(actual_12 == expected_12, actual_12, expected_12)
  Nil
}

pub fn rejects_non_success_status_without_retaining_body_data_test() -> Nil {
  let actual_13 = scenario("status", connection.Ipv4)
  let expected_13 = Ok(Nil)
  let assert #(True, _, _) = #(actual_13 == expected_13, actual_13, expected_13)
  Nil
}

pub fn enforces_cumulative_bytes_including_final_chunked_data_test() -> Nil {
  let actual_14 = scenario("chunked", connection.Ipv4)
  let expected_14 = Ok(Nil)
  let assert #(True, _, _) = #(actual_14 == expected_14, actual_14, expected_14)
  Nil
}

pub fn enforces_cumulative_bytes_on_close_delimited_bodies_test() -> Nil {
  let actual_15 = scenario("close", connection.Ipv4)
  let expected_15 = Ok(Nil)
  let assert #(True, _, _) = #(actual_15 == expected_15, actual_15, expected_15)
  Nil
}

pub fn bounds_stalled_response_headers_and_cleans_up_test() -> Nil {
  let actual_16 = scenario("headers_stall", connection.Ipv4)
  let expected_16 = Ok(Nil)
  let assert #(True, _, _) = #(actual_16 == expected_16, actual_16, expected_16)
  Nil
}

pub fn bounds_stalled_response_data_and_cleans_up_test() -> Nil {
  let actual_17 = scenario("body_stall", connection.Ipv4)
  let expected_17 = Ok(Nil)
  let assert #(True, _, _) = #(actual_17 == expected_17, actual_17, expected_17)
  Nil
}

pub fn bounds_a_dribbling_response_with_a_monotonic_total_deadline_test() -> Nil {
  let actual_18 = scenario("deadline", connection.Ipv4)
  let expected_18 = Ok(Nil)
  let assert #(True, _, _) = #(actual_18 == expected_18, actual_18, expected_18)
  Nil
}

pub fn bounds_stalled_tls_handshake_with_retries_disabled_test() -> Nil {
  let actual_19 = scenario("tls_stall", connection.Ipv4)
  let expected_19 = Ok(Nil)
  let assert #(True, _, _) = #(actual_19 == expected_19, actual_19, expected_19)
  Nil
}

pub fn interrupts_setup_before_its_stage_timeout_expires_test() -> Nil {
  let actual_20 = scenario("setup_deadline", connection.Ipv4)
  let expected_20 = Ok(Nil)
  let assert #(True, _, _) = #(actual_20 == expected_20, actual_20, expected_20)
  Nil
}

pub fn interrupts_a_gun_process_blocked_at_dns_setup_test() -> Nil {
  let actual_21 = scenario("dns_deadline", connection.Ipv4)
  let expected_21 = Ok(Nil)
  let assert #(True, _, _) = #(actual_21 == expected_21, actual_21, expected_21)
  Nil
}

pub fn interrupts_a_gun_process_blocked_at_socket_setup_test() -> Nil {
  let actual_22 = scenario("connect_deadline", connection.Ipv4)
  let expected_22 = Ok(Nil)
  let assert #(True, _, _) = #(actual_22 == expected_22, actual_22, expected_22)
  Nil
}

pub fn selects_only_ipv4_without_ipv6_fallback_test() -> Nil {
  let actual_23 = scenario("family", connection.Ipv4)
  let expected_23 = Ok(Nil)
  let assert #(True, _, _) = #(actual_23 == expected_23, actual_23, expected_23)
  Nil
}

pub fn selects_only_ipv6_without_ipv4_fallback_test() -> Nil {
  let actual_24 = scenario("family", connection.Ipv6)
  let expected_24 = Ok(Nil)
  let assert #(True, _, _) = #(actual_24 == expected_24, actual_24, expected_24)
  Nil
}

pub fn preserves_tls_verification_with_ipv4_selection_test() -> Nil {
  let actual_25 = {
    configured(connection.Ipv4)
    |> connection.options_to_ffi
    |> verify_tls
  }
  let expected_25 = Ok(Nil)
  let assert #(True, _, _) = #(actual_25 == expected_25, actual_25, expected_25)
  Nil
}

pub fn preserves_tls_verification_with_ipv6_selection_test() -> Nil {
  let actual_26 = {
    configured(connection.Ipv6)
    |> connection.options_to_ffi
    |> verify_tls
  }
  let expected_26 = Ok(Nil)
  let assert #(True, _, _) = #(actual_26 == expected_26, actual_26, expected_26)
  Nil
}

pub fn terminates_a_blocked_sender_and_preserves_unrelated_mail_test() -> Nil {
  let actual_27 = cleanup()
  let expected_27 = Ok(Nil)
  let assert #(True, _, _) = #(actual_27 == expected_27, actual_27, expected_27)
  Nil
}

pub fn pauses_and_resumes_a_live_http_2_stream_byte_window_test() -> Nil {
  let actual_28 = http2_scenario("flow")
  let expected_28 = Ok(Nil)
  let assert #(True, _, _) = #(actual_28 == expected_28, actual_28, expected_28)
  Nil
}

pub fn checks_final_http_2_data_bytes_and_closes_the_peer_test() -> Nil {
  let actual_29 = http2_scenario("limit")
  let expected_29 = Ok(Nil)
  let assert #(True, _, _) = #(actual_29 == expected_29, actual_29, expected_29)
  Nil
}

pub fn drains_a_real_queued_http_2_push_after_termination_test() -> Nil {
  let actual_30 = http2_scenario("cleanup")
  let expected_30 = Ok(Nil)
  let assert #(True, _, _) = #(actual_30 == expected_30, actual_30, expected_30)
  Nil
}

fn timeout(value: Int) -> connection.Timeout {
  let assert Ok(timeout) = connection.milliseconds(value)
  timeout
}

fn configured(family: connection.AddressFamily) -> connection.ConnectOptions {
  let assert Ok(retries) = connection.retry_count(0)
  connection.options()
  |> connection.with_transport(connection.Tcp)
  |> connection.with_address_family(family)
  |> connection.with_retry(retries)
  |> connection.with_connect_timeout(timeout(200))
  |> connection.with_domain_lookup_timeout(timeout(200))
  |> connection.with_tls_handshake_timeout(timeout(200))
}

fn scenario(
  name: String,
  family: connection.AddressFamily,
) -> Result(Nil, error.GluegunError) {
  let assert Ok(options) = request.with_initial_flow(request.options(), 1)
  run_scenario(
    name,
    configured(family) |> connection.options_to_ffi,
    request.options_to_ffi(options),
  )
}

fn http2_scenario(mode: String) -> Result(Nil, error.GluegunError) {
  let assert Ok(options) = request.with_initial_flow(request.options(), 1)
  run_http2(
    mode,
    configured(connection.Ipv4)
      |> connection.with_protocols([connection.Http2])
      |> connection.options_to_ffi,
    request.options_to_ffi(options),
  )
}

@external(erlang, "gluegun_http2_test", "run")
fn run_http2(
  mode: String,
  connection_options: List(connection.ConnectOption),
  request_options: List(request.RequestOption),
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_bounded_test", "capture_flow")
fn capture_flow(
  options: List(request.RequestOption),
) -> Result(#(String, String), error.GluegunError)

@external(erlang, "gluegun_bounded_test", "project_setup")
fn project_setup(
  options: List(connection.ConnectOption),
) -> #(String, String, String, String, String, Bool)

@external(erlang, "gluegun_bounded_test", "invalid_options")
fn invalid_options() -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_bounded_test", "run_scenario")
fn run_scenario(
  name: String,
  connection_options: List(connection.ConnectOption),
  request_options: List(request.RequestOption),
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_bounded_test", "cleanup")
fn cleanup() -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_bounded_test", "verify_tls")
fn verify_tls(
  options: List(connection.ConnectOption),
) -> Result(Nil, error.GluegunError)
