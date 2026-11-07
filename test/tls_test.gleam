import gleam/option.{type Option, None, Some}
import gluegun/connection
import gluegun/error
import gluegun/tls

/// Gun `tls_opts()` projected back into Gleam by `gluegun_ffi_test`:
/// `#(verify, versions, depth, server_name_indication, has_cacerts,
/// has_hostname_check)`.
type TlsSummary =
  #(
    Option(String),
    Option(List(String)),
    Option(Int),
    Option(String),
    Bool,
    Bool,
  )

pub fn nests_tls_options_under_transport_opts_in_connection_ffi_test() -> Nil {
  let options =
    connection.options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.with_tls_options(
      tls.options()
      |> tls.with_verify(verify: tls.VerifyPeer)
      |> tls.with_versions(versions: [tls.TlsV12, tls.TlsV13]),
    )

  let actual_1 = connection.options_to_ffi(options)
  let expected_1 = [
    connection.TransportOption(connection.Tls),
    connection.RetryOption(connection.default_retry_count()),
    connection.ConnectTimeoutOption(connection.default_timeout()),
    connection.TlsOption([
      tls.VerifySetting(tls.VerifyPeer),
      tls.VersionsSetting([tls.TlsV12, tls.TlsV13]),
    ]),
  ]
  let assert #(True, _, _) = #(actual_1 == expected_1, actual_1, expected_1)
  Nil
}

pub fn converts_nested_tls_options_to_gun_tls_opts_test() -> Nil {
  let tls_options =
    tls.options()
    |> tls.with_verify(verify: tls.VerifyPeer)
    |> tls.with_versions(versions: [tls.TlsV12, tls.TlsV13])

  let actual_2 = {
    connection.options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.with_tls_options(tls_options)
    |> connection.options_to_ffi
    |> gun_tls_options
  }
  let expected_2 = [
    #("verify", ["verify_peer"]),
    #("versions", ["tlsv1.2", "tlsv1.3"]),
  ]
  let assert #(True, _, _) = #(actual_2 == expected_2, actual_2, expected_2)
  Nil
}

pub fn includes_tls_options_for_auto_transport_test() -> Nil {
  let tls_options = tls.options() |> tls.with_verify(verify: tls.VerifyPeer)

  let actual_3 = {
    connection.options()
    |> connection.with_tls_options(tls_options)
    |> connection.options_to_ffi
  }
  let expected_3 = [
    connection.TransportOption(connection.Auto),
    connection.RetryOption(connection.default_retry_count()),
    connection.ConnectTimeoutOption(connection.default_timeout()),
    connection.TlsOption([tls.VerifySetting(tls.VerifyPeer)]),
  ]
  let assert #(True, _, _) = #(actual_3 == expected_3, actual_3, expected_3)
  Nil
}

pub fn resolves_auto_to_gun_s_tls_transport_when_tls_options_are_configured_preventing_a_silent_downgrade_to_plaintext_on_non_443_ports_test() -> Nil {
  let tls_options = tls.options() |> tls.with_verify(verify: tls.VerifyPeer)

  let actual_4 = {
    connection.options()
    |> connection.with_tls_options(tls_options)
    |> connection.options_to_ffi
    |> gun_transport
  }
  let expected_4 = "tls"
  let assert #(True, _, _) = #(actual_4 == expected_4, actual_4, expected_4)
  Nil
}

pub fn leaves_auto_unresolved_for_gun_s_own_port_based_default_when_no_tls_options_are_configured_test() -> Nil {
  let actual_5 = {
    connection.options()
    |> connection.options_to_ffi
    |> gun_transport
  }
  let expected_5 = "undefined"
  let assert #(True, _, _) = #(actual_5 == expected_5, actual_5, expected_5)
  Nil
}

pub fn keeps_the_resolved_gun_transport_as_tcp_when_transport_is_explicitly_tcp_test() -> Nil {
  let actual_6 = {
    connection.options()
    |> connection.with_transport(transport: connection.Tcp)
    |> connection.options_to_ffi
    |> gun_transport
  }
  let expected_6 = "tcp"
  let assert #(True, _, _) = #(actual_6 == expected_6, actual_6, expected_6)
  Nil
}

pub fn keeps_the_resolved_gun_transport_as_tls_when_transport_is_explicitly_tls_test() -> Nil {
  let actual_7 = {
    connection.options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.options_to_ffi
    |> gun_transport
  }
  let expected_7 = "tls"
  let assert #(True, _, _) = #(actual_7 == expected_7, actual_7, expected_7)
  Nil
}

pub fn skips_tls_transport_options_for_tcp_connections_test() -> Nil {
  let tls_options = tls.options() |> tls.with_verify(verify: tls.VerifyPeer)

  let actual_8 = {
    connection.options()
    |> connection.with_transport(transport: connection.Tcp)
    |> connection.with_tls_options(tls_options)
    |> connection.options_to_ffi
  }
  let expected_8 = [
    connection.TransportOption(connection.Tcp),
    connection.RetryOption(connection.default_retry_count()),
    connection.ConnectTimeoutOption(connection.default_timeout()),
  ]
  let assert #(True, _, _) = #(actual_8 == expected_8, actual_8, expected_8)
  Nil
}

pub fn applies_the_secure_baseline_when_tls_is_used_and_no_options_are_set_test() -> Nil {
  let options =
    connection.options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.options_to_ffi

  let actual_9 = gun_secure_tls_summary("example.com", options)
  let expected_9 =
    secure_tls_summary(
      server_name_indication: Some("example.com"),
      versions: default_versions(),
      depth: Some(10),
      has_cacerts: True,
      has_hostname_check: True,
    )
  let assert #(True, _, _) = #(actual_9 == expected_9, actual_9, expected_9)
  Nil
}

pub fn lets_user_set_tls_fields_override_the_secure_baseline_test() -> Nil {
  let tls_options =
    tls.options()
    |> tls.with_versions(versions: [tls.TlsV13])
    |> tls.with_depth(depth: 3)
    |> tls.with_server_name_indication(server_name_indication: tls.ServerName(
      "override.example",
    ))

  let options =
    connection.options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.with_tls_options(tls_options)
    |> connection.options_to_ffi

  let actual_10 = gun_secure_tls_summary("example.com", options)
  let expected_10 =
    secure_tls_summary(
      server_name_indication: Some("override.example"),
      versions: Some(["tlsv1.3"]),
      depth: Some(3),
      has_cacerts: True,
      has_hostname_check: True,
    )
  let assert #(True, _, _) = #(actual_10 == expected_10, actual_10, expected_10)
  Nil
}

pub fn documented_custom_ca_options_use_the_public_tls_builder_test() -> Nil {
  let tls_options =
    tls.options()
    |> tls.with_versions(versions: [tls.TlsV13])
    |> tls.with_cacertfile(cacertfile: "/etc/ssl/cert.pem")
    |> tls.with_depth(depth: 5)

  let options =
    connection.options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.with_tls_options(tls_options: tls_options)
    |> connection.options_to_ffi

  let actual = options |> gun_tls_options
  let expected = [
    #("versions", ["tlsv1.3"]),
    #("cacertfile", ["/etc/ssl/cert.pem"]),
    #("depth", ["5"]),
  ]
  let assert #(True, _, _) = #(actual == expected, actual, expected)
  Nil
}

pub fn tls_insecure_suppresses_the_secure_baseline_test() -> Nil {
  let options =
    connection.options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.with_tls_options(tls_options: tls.insecure())
    |> connection.options_to_ffi

  let actual_11 = gun_secure_tls_summary("example.com", options)
  let expected_11 = insecure_tls_summary()
  let assert #(True, _, _) = #(actual_11 == expected_11, actual_11, expected_11)
  Nil
}

pub fn skips_sni_when_host_is_an_ip_literal_test() -> Nil {
  let options =
    connection.options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.options_to_ffi

  let actual_12 = gun_secure_tls_summary("127.0.0.1", options)
  let expected_12 =
    secure_tls_summary(
      server_name_indication: None,
      versions: default_versions(),
      depth: Some(10),
      has_cacerts: True,
      has_hostname_check: True,
    )
  let assert #(True, _, _) = #(actual_12 == expected_12, actual_12, expected_12)
  Nil
}

pub fn skips_sni_when_host_is_a_bracketed_ipv6_literal_test() -> Nil {
  let options =
    connection.options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.options_to_ffi

  let actual_13 = gun_secure_tls_summary("[::1]", options)
  let expected_13 =
    secure_tls_summary(
      server_name_indication: None,
      versions: default_versions(),
      depth: Some(10),
      has_cacerts: True,
      has_hostname_check: True,
    )
  let assert #(True, _, _) = #(actual_13 == expected_13, actual_13, expected_13)

  let actual_14 = gun_secure_tls_summary("[2001:db8::1]", options)
  let expected_14 =
    secure_tls_summary(
      server_name_indication: None,
      versions: default_versions(),
      depth: Some(10),
      has_cacerts: True,
      has_hostname_check: True,
    )
  let assert #(True, _, _) = #(actual_14 == expected_14, actual_14, expected_14)
  Nil
}

pub fn applies_the_secure_baseline_for_auto_transport_too_test() -> Nil {
  let options =
    connection.options()
    |> connection.options_to_ffi

  let actual_15 = gun_secure_tls_summary("example.com", options)
  let expected_15 =
    secure_tls_summary(
      server_name_indication: Some("example.com"),
      versions: default_versions(),
      depth: Some(10),
      has_cacerts: True,
      has_hostname_check: True,
    )
  let assert #(True, _, _) = #(actual_15 == expected_15, actual_15, expected_15)
  Nil
}

pub fn does_not_apply_the_secure_baseline_for_tcp_transport_test() -> Nil {
  let options =
    connection.options()
    |> connection.with_transport(transport: connection.Tcp)
    |> connection.options_to_ffi

  let actual_16 = gun_secure_tls_summary("example.com", options)
  let expected_16 =
    tls_summary(
      verify: None,
      versions: None,
      depth: None,
      server_name_indication: None,
      has_cacerts: False,
      has_hostname_check: False,
    )
  let assert #(True, _, _) = #(actual_16 == expected_16, actual_16, expected_16)
  Nil
}

pub fn returns_invalidoptions_when_secure_defaults_cannot_load_system_cas_test() -> Nil {
  let options =
    connection.options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.options_to_ffi

  let actual_17 =
    gun_secure_tls_summary_with_empty_cacerts("example.com", options)
  let expected_17 = Error(error.InvalidOptions("Tls(NoSystemCacerts(Empty))"))
  let assert #(True, _, _) = #(actual_17 == expected_17, actual_17, expected_17)
  Nil
}

pub fn returns_invalidoptions_when_hostname_match_function_is_unavailable_test() -> Nil {
  let options =
    connection.options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.options_to_ffi

  let actual_18 =
    gun_secure_tls_summary_with_hostname_match_failure("example.com", options)
  let expected_18 =
    Error(error.InvalidOptions(
      "Tls(HostnameMatchFunUnavailable(Error(TestHostnameMatchFailure)))",
    ))
  let assert #(True, _, _) = #(actual_18 == expected_18, actual_18, expected_18)
  Nil
}

pub fn caches_system_ca_certificates_after_the_first_successful_load_test() -> Nil {
  let options =
    connection.options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.options_to_ffi

  let actual_19 = gun_secure_tls_cacerts_load_count("example.com", options)
  let expected_19 = 1
  let assert #(True, _, _) = #(actual_19 == expected_19, actual_19, expected_19)
  Nil
}

@external(erlang, "gluegun_ffi_test", "gun_tls_opts")
fn gun_tls_options(
  options: List(connection.ConnectOption),
) -> List(#(String, List(String)))

/// Gun's resolved `transport` option after `connect_options_to_gun`, or
/// `"undefined"` when left unset for Gun's own port-based default.
@external(erlang, "gluegun_ffi_test", "gun_transport")
fn gun_transport(options: List(connection.ConnectOption)) -> String

@external(erlang, "gluegun_ffi_test", "secure_tls_opts_summary")
fn gun_secure_tls_summary(
  host: String,
  options: List(connection.ConnectOption),
) -> TlsSummary

@external(erlang, "gluegun_ffi_test", "secure_tls_opts_with_empty_cacerts")
fn gun_secure_tls_summary_with_empty_cacerts(
  host: String,
  options: List(connection.ConnectOption),
) -> Result(TlsSummary, error.GluegunError)

@external(erlang, "gluegun_ffi_test", "secure_tls_opts_with_hostname_match_failure")
fn gun_secure_tls_summary_with_hostname_match_failure(
  host: String,
  options: List(connection.ConnectOption),
) -> Result(TlsSummary, error.GluegunError)

@external(erlang, "gluegun_ffi_test", "secure_tls_opts_caches_cacerts")
fn gun_secure_tls_cacerts_load_count(
  host: String,
  options: List(connection.ConnectOption),
) -> Int

fn secure_tls_summary(
  server_name_indication server_name_indication: Option(String),
  versions versions: Option(List(String)),
  depth depth: Option(Int),
  has_cacerts has_cacerts: Bool,
  has_hostname_check has_hostname_check: Bool,
) -> TlsSummary {
  tls_summary(
    verify: Some("verify_peer"),
    versions: versions,
    depth: depth,
    server_name_indication: server_name_indication,
    has_cacerts: has_cacerts,
    has_hostname_check: has_hostname_check,
  )
}

fn insecure_tls_summary() -> TlsSummary {
  tls_summary(
    verify: Some("verify_none"),
    versions: None,
    depth: None,
    server_name_indication: Some("disable"),
    has_cacerts: False,
    has_hostname_check: False,
  )
}

fn tls_summary(
  verify verify: Option(String),
  versions versions: Option(List(String)),
  depth depth: Option(Int),
  server_name_indication server_name_indication: Option(String),
  has_cacerts has_cacerts: Bool,
  has_hostname_check has_hostname_check: Bool,
) -> TlsSummary {
  #(
    verify,
    versions,
    depth,
    server_name_indication,
    has_cacerts,
    has_hostname_check,
  )
}

fn default_versions() -> Option(List(String)) {
  Some(["tlsv1.3", "tlsv1.2"])
}
