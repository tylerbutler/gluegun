import gluegun/connection
import gluegun/error
import gluegun/request
import startest
import startest/expect
import startest/test_tree

pub fn bounded_streaming_tests() -> test_tree.TestTree {
  startest.describe("bounded streaming and setup", [
    startest.it("converts finite credit for both request entry points", fn() {
      let assert Ok(options) = request.options() |> request.with_initial_flow(1)
      options
      |> request.with_headers([#("accept", "text/plain")])
      |> request.add_headers([#("x-test", "flow")])
      |> request.options_to_ffi
      |> capture_flow
      |> expect.to_equal(Ok(#("1", "1")))
      request.options()
      |> request.options_to_ffi
      |> capture_flow
      |> expect.to_equal(Ok(#("infinity", "infinity")))
    }),
    startest.it("rejects non-positive initial credit", fn() {
      request.with_initial_flow(request.options(), 0)
      |> expect.to_equal(
        Error(error.InvalidOptions("initial flow credit must be positive")),
      )
      request.with_initial_flow(request.options(), -1)
      |> expect.to_equal(
        Error(error.InvalidOptions("initial flow credit must be positive")),
      )
    }),
    startest.it("rejects negative retry counts and accepts zero", fn() {
      connection.retry_count(-1)
      |> expect.to_equal(
        Error(error.InvalidOptions("retry count must be non-negative")),
      )
      configured(connection.Ipv4)
      |> connection.options_to_ffi
      |> project_setup
      |> expect.to_equal(#("inet", "0", "200", "200", "200", True))
    }),
    startest.it("preserves setup defaults and infinite stage timeouts", fn() {
      connection.options()
      |> connection.options_to_ffi
      |> project_setup
      |> expect.to_equal(#("default", "5", "5000", "infinity", "infinity", True))
      connection.options()
      |> connection.with_address_family(connection.Ipv6)
      |> connection.with_domain_lookup_timeout(connection.infinity())
      |> connection.with_tls_handshake_timeout(timeout(0))
      |> connection.options_to_ffi
      |> project_setup
      |> expect.to_equal(#("inet6", "5", "5000", "infinity", "0", True))
    }),
    startest.it("rejects invalid raw FFI options", fn() {
      invalid_options() |> expect.to_equal(Ok(Nil))
    }),
    startest.it("pauses one large HTTP chunk until credit is granted", fn() {
      scenario("large", connection.Ipv4) |> expect.to_equal(Ok(Nil))
    }),
    startest.it("pauses many small HTTP chunks until credit is granted", fn() {
      scenario("small", connection.Ipv4) |> expect.to_equal(Ok(Nil))
    }),
    startest.it(
      "rejects oversized Content-Length before body transmission",
      fn() { scenario("length", connection.Ipv4) |> expect.to_equal(Ok(Nil)) },
    ),
    startest.it("rejects non-success status without retaining body data", fn() {
      scenario("status", connection.Ipv4) |> expect.to_equal(Ok(Nil))
    }),
    startest.it("enforces cumulative bytes including final chunked data", fn() {
      scenario("chunked", connection.Ipv4) |> expect.to_equal(Ok(Nil))
    }),
    startest.it("enforces cumulative bytes on close-delimited bodies", fn() {
      scenario("close", connection.Ipv4) |> expect.to_equal(Ok(Nil))
    }),
    startest.it("bounds stalled response headers and cleans up", fn() {
      scenario("headers_stall", connection.Ipv4) |> expect.to_equal(Ok(Nil))
    }),
    startest.it("bounds stalled response data and cleans up", fn() {
      scenario("body_stall", connection.Ipv4) |> expect.to_equal(Ok(Nil))
    }),
    startest.it(
      "bounds a dribbling response with a monotonic total deadline",
      fn() { scenario("deadline", connection.Ipv4) |> expect.to_equal(Ok(Nil)) },
    ),
    startest.it("bounds stalled TLS handshake with retries disabled", fn() {
      scenario("tls_stall", connection.Ipv4) |> expect.to_equal(Ok(Nil))
    }),
    startest.it("interrupts setup before its stage timeout expires", fn() {
      scenario("setup_deadline", connection.Ipv4) |> expect.to_equal(Ok(Nil))
    }),
    startest.it("interrupts a Gun process blocked at DNS setup", fn() {
      scenario("dns_deadline", connection.Ipv4) |> expect.to_equal(Ok(Nil))
    }),
    startest.it("interrupts a Gun process blocked at socket setup", fn() {
      scenario("connect_deadline", connection.Ipv4) |> expect.to_equal(Ok(Nil))
    }),
    startest.it("selects only IPv4 without IPv6 fallback", fn() {
      scenario("family", connection.Ipv4) |> expect.to_equal(Ok(Nil))
    }),
    startest.it("selects only IPv6 without IPv4 fallback", fn() {
      scenario("family", connection.Ipv6) |> expect.to_equal(Ok(Nil))
    }),
    startest.it("preserves TLS verification with IPv4 selection", fn() {
      configured(connection.Ipv4)
      |> connection.options_to_ffi
      |> verify_tls
      |> expect.to_equal(Ok(Nil))
    }),
    startest.it("preserves TLS verification with IPv6 selection", fn() {
      configured(connection.Ipv6)
      |> connection.options_to_ffi
      |> verify_tls
      |> expect.to_equal(Ok(Nil))
    }),
    startest.it(
      "terminates a blocked sender and preserves unrelated mail",
      fn() { cleanup() |> expect.to_equal(Ok(Nil)) },
    ),
    startest.it("pauses and resumes a live HTTP/2 stream byte window", fn() {
      http2_scenario("flow") |> expect.to_equal(Ok(Nil))
    }),
    startest.it("checks final HTTP/2 data bytes and closes the peer", fn() {
      http2_scenario("limit") |> expect.to_equal(Ok(Nil))
    }),
    startest.it("drains a real queued HTTP/2 push after termination", fn() {
      http2_scenario("cleanup") |> expect.to_equal(Ok(Nil))
    }),
  ])
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
