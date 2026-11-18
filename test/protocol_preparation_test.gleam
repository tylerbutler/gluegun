import gleam/option.{type Option, None, Some}
import gluegun/client
import gluegun/connection
import gluegun/error
import gluegun/response
import gluegun/tls

pub fn tcp_prepares_http2_first_test() -> Nil {
  assert_prepared(
    preferences(connection.Tcp, [connection.Http2, connection.Http1]),
    80,
    connection.Tcp,
    Some([connection.Http2]),
  )
}

pub fn tcp_prepares_http1_first_test() -> Nil {
  assert_prepared(
    preferences(connection.Tcp, [connection.Http1, connection.Http2]),
    80,
    connection.Tcp,
    Some([connection.Http1]),
  )
}

pub fn auto_tcp_prepares_http2_first_test() -> Nil {
  assert_prepared(
    preferences(connection.Auto, [connection.Http2, connection.Http1]),
    8080,
    connection.Tcp,
    Some([connection.Http2]),
  )
}

pub fn auto_tcp_prepares_http1_first_test() -> Nil {
  assert_prepared(
    preferences(connection.Auto, [connection.Http1, connection.Http2]),
    8080,
    connection.Tcp,
    Some([connection.Http1]),
  )
}

pub fn tcp_preserves_omitted_protocols_test() -> Nil {
  assert_prepared(
    connection.options() |> connection.with_transport(connection.Tcp),
    443,
    connection.Tcp,
    None,
  )
}

pub fn auto_tcp_preserves_omitted_protocols_test() -> Nil {
  assert_prepared(connection.options(), 8080, connection.Tcp, None)
}

pub fn tcp_preserves_http1_singleton_test() -> Nil {
  assert_prepared(
    preferences(connection.Tcp, [connection.Http1]),
    80,
    connection.Tcp,
    Some([connection.Http1]),
  )
}

pub fn tcp_preserves_http2_singleton_test() -> Nil {
  assert_prepared(
    preferences(connection.Tcp, [connection.Http2]),
    80,
    connection.Tcp,
    Some([connection.Http2]),
  )
}

pub fn tls_preserves_http2_first_test() -> Nil {
  assert_prepared(
    with_test_tls(
      preferences(connection.Tls, [connection.Http2, connection.Http1]),
    ),
    8443,
    connection.Tls,
    Some([connection.Http2, connection.Http1]),
  )
}

pub fn tls_preserves_http1_first_test() -> Nil {
  assert_prepared(
    with_test_tls(
      preferences(connection.Tls, [connection.Http1, connection.Http2]),
    ),
    8443,
    connection.Tls,
    Some([connection.Http1, connection.Http2]),
  )
}

pub fn auto_443_preserves_tls_protocols_test() -> Nil {
  assert_prepared(
    preferences(connection.Auto, [connection.Http2, connection.Http1]),
    443,
    connection.Tls,
    Some([connection.Http2, connection.Http1]),
  )
}

pub fn auto_configured_tls_preserves_http2_first_on_non443_test() -> Nil {
  assert_prepared(
    with_test_tls(
      preferences(connection.Auto, [connection.Http2, connection.Http1]),
    ),
    8080,
    connection.Tls,
    Some([connection.Http2, connection.Http1]),
  )
}

pub fn auto_configured_tls_preserves_http1_first_on_non443_test() -> Nil {
  assert_prepared(
    with_test_tls(
      preferences(connection.Auto, [connection.Http1, connection.Http2]),
    ),
    8080,
    connection.Tls,
    Some([connection.Http1, connection.Http2]),
  )
}

pub fn auto_empty_tls_settings_preserves_http2_first_on_non443_test() -> Nil {
  assert_prepared(
    preferences(connection.Auto, [connection.Http2, connection.Http1])
      |> connection.with_tls_options(tls.options()),
    8080,
    connection.Tls,
    Some([connection.Http2, connection.Http1]),
  )
}

pub fn auto_empty_tls_settings_preserves_http1_first_on_non443_test() -> Nil {
  assert_prepared(
    preferences(connection.Auto, [connection.Http1, connection.Http2])
      |> connection.with_tls_options(tls.options()),
    8080,
    connection.Tls,
    Some([connection.Http1, connection.Http2]),
  )
}

pub fn tls_preserves_omitted_protocols_test() -> Nil {
  assert_prepared(
    with_test_tls(
      connection.options() |> connection.with_transport(connection.Tls),
    ),
    8443,
    connection.Tls,
    None,
  )
}

pub fn tcp_rejects_empty_before_open_test() -> Nil {
  assert_empty_rejected(preferences(connection.Tcp, []), 80)
}

pub fn auto_tcp_rejects_empty_before_open_test() -> Nil {
  assert_empty_rejected(preferences(connection.Auto, []), 8080)
}

pub fn tls_rejects_empty_before_open_test() -> Nil {
  assert_empty_rejected(preferences(connection.Tls, []), 8443)
}

pub fn auto_443_rejects_empty_before_open_test() -> Nil {
  assert_empty_rejected(preferences(connection.Auto, []), 443)
}

pub fn auto_configured_tls_rejects_empty_test() -> Nil {
  assert_empty_rejected(with_test_tls(preferences(connection.Auto, [])), 8080)
}

pub fn tcp_http2_first_public_loopback_test() -> Nil {
  assert_loopback(
    preferences(connection.Tcp, [connection.Http2, connection.Http1]),
    connection.Http2,
  )
}

pub fn tcp_http1_first_public_loopback_test() -> Nil {
  assert_loopback(
    preferences(connection.Tcp, [connection.Http1, connection.Http2]),
    connection.Http1,
  )
}

pub fn auto_tcp_http2_first_public_loopback_test() -> Nil {
  assert_loopback(
    preferences(connection.Auto, [connection.Http2, connection.Http1]),
    connection.Http2,
  )
}

pub fn auto_tcp_http1_first_public_loopback_test() -> Nil {
  assert_loopback(
    preferences(connection.Auto, [connection.Http1, connection.Http2]),
    connection.Http1,
  )
}

pub fn tcp_omitted_public_loopback_test() -> Nil {
  assert_loopback(
    connection.options() |> connection.with_transport(connection.Tcp),
    connection.Http1,
  )
}

pub fn auto_tcp_omitted_public_loopback_test() -> Nil {
  assert_loopback(connection.options(), connection.Http1)
}

pub fn tcp_http1_singleton_public_loopback_test() -> Nil {
  assert_loopback(
    preferences(connection.Tcp, [connection.Http1]),
    connection.Http1,
  )
}

pub fn tcp_http2_singleton_public_loopback_test() -> Nil {
  assert_loopback(
    preferences(connection.Tcp, [connection.Http2]),
    connection.Http2,
  )
}

pub fn auto_tcp_http1_singleton_public_loopback_test() -> Nil {
  assert_loopback(
    preferences(connection.Auto, [connection.Http1]),
    connection.Http1,
  )
}

pub fn auto_tcp_http2_singleton_public_loopback_test() -> Nil {
  assert_loopback(
    preferences(connection.Auto, [connection.Http2]),
    connection.Http2,
  )
}

fn preferences(
  transport: connection.Transport,
  protocols: List(connection.Protocol),
) -> connection.ConnectOptions {
  connection.options()
  |> connection.with_transport(transport)
  |> connection.with_protocols(protocols)
}

fn with_test_tls(
  options: connection.ConnectOptions,
) -> connection.ConnectOptions {
  options
  |> connection.with_tls_options(
    tls.options() |> tls.with_verify(tls.VerifyNone),
  )
}

fn assert_prepared(
  options: connection.ConnectOptions,
  port: Int,
  transport: connection.Transport,
  protocols: Option(List(connection.Protocol)),
) -> Nil {
  let actual =
    prepared_protocol_options(
      "localhost",
      port,
      connection.options_to_ffi(options),
    )
  assert actual == Ok(#(transport, protocols))
}

fn assert_empty_rejected(options: connection.ConnectOptions, port: Int) -> Nil {
  let expected = error.InvalidOptions("Protocols([])")
  assert prepared_protocol_options(
      "localhost",
      port,
      connection.options_to_ffi(options),
    )
    == Error(expected)
  let actual = connection.open(options, host: "127.0.0.1", port: port)
  // Keep the red run leak-free even if the invalid options create a process.
  case actual {
    Ok(opened) -> {
      let assert Ok(Nil) = connection.terminate(opened)
      Nil
    }
    Error(_) -> Nil
  }
  assert actual == Error(expected)
}

fn assert_loopback(
  options: connection.ConnectOptions,
  protocol: connection.Protocol,
) -> Nil {
  let assert Ok(Nil) =
    with_protocol_server(protocol, fn(port) {
      let assert Ok(opened) =
        connection.open(options, host: "127.0.0.1", port: port)
      use <- with_connection(opened)
      let assert Ok(timeout) = connection.milliseconds(2000)
      let assert Ok(negotiated) = connection.await_up(opened, timeout)
      assert negotiated == protocol
      let assert Ok(reply) = client.get(opened, "/", [], timeout)
      assert response.status(reply) == 200
      assert response.body(reply) == <<"selected":utf8>>
      connection.terminate(opened)
    })
  Nil
}

@external(erlang, "gluegun_ffi_test", "prepared_protocol_options")
fn prepared_protocol_options(
  host: String,
  port: Int,
  options: List(connection.ConnectOption),
) -> Result(
  #(connection.Transport, Option(List(connection.Protocol))),
  error.GluegunError,
)

@external(erlang, "gluegun_http2_test", "with_protocol_server")
fn with_protocol_server(
  protocol: connection.Protocol,
  callback: fn(Int) -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_runtime_regression_test", "with_connection")
fn with_connection(
  connection: connection.Connection,
  callback: fn() -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)
