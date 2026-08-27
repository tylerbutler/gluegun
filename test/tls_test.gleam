import gleam/option.{type Option, None, Some}
import gluegun/connection
import gluegun/error
import gluegun/tls
import startest
import startest/expect
import startest/test_tree

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

pub fn tls_tests() -> test_tree.TestTree {
  startest.describe("TLS option encoding", [
    startest.it(
      "nests TLS options under transport_opts in connection FFI",
      fn() {
        let options =
          connection.options()
          |> connection.with_transport(transport: connection.Tls)
          |> connection.with_tls_options(
            tls.options()
            |> tls.with_verify(verify: tls.VerifyPeer)
            |> tls.with_versions(versions: [tls.TlsV12, tls.TlsV13]),
          )

        connection.options_to_ffi(options)
        |> expect.to_equal([
          connection.TransportOption(connection.Tls),
          connection.RetryOption(connection.Milliseconds(5000)),
          connection.ConnectTimeoutOption(connection.Milliseconds(5000)),
          connection.TlsOption([
            tls.VerifySetting(tls.VerifyPeer),
            tls.VersionsSetting([tls.TlsV12, tls.TlsV13]),
          ]),
        ])
      },
    ),

    startest.it("converts nested TLS options to Gun tls_opts", fn() {
      let tls_options =
        tls.options()
        |> tls.with_verify(verify: tls.VerifyPeer)
        |> tls.with_versions(versions: [tls.TlsV12, tls.TlsV13])

      connection.options()
      |> connection.with_transport(transport: connection.Tls)
      |> connection.with_tls_options(tls_options)
      |> connection.options_to_ffi
      |> gun_tls_options
      |> expect.to_equal([
        #("verify", ["verify_peer"]),
        #("versions", ["tlsv1.2", "tlsv1.3"]),
      ])
    }),

    startest.it("includes TLS options for auto transport", fn() {
      let tls_options = tls.options() |> tls.with_verify(verify: tls.VerifyPeer)

      connection.options()
      |> connection.with_tls_options(tls_options)
      |> connection.options_to_ffi
      |> expect.to_equal([
        connection.TransportOption(connection.Auto),
        connection.RetryOption(connection.Milliseconds(5000)),
        connection.ConnectTimeoutOption(connection.Milliseconds(5000)),
        connection.TlsOption([tls.VerifySetting(tls.VerifyPeer)]),
      ])
    }),

    startest.it("skips TLS transport options for TCP connections", fn() {
      let tls_options = tls.options() |> tls.with_verify(verify: tls.VerifyPeer)

      connection.options()
      |> connection.with_transport(transport: connection.Tcp)
      |> connection.with_tls_options(tls_options)
      |> connection.options_to_ffi
      |> expect.to_equal([
        connection.TransportOption(connection.Tcp),
        connection.RetryOption(connection.Milliseconds(5000)),
        connection.ConnectTimeoutOption(connection.Milliseconds(5000)),
      ])
    }),

    startest.it(
      "applies the secure baseline when TLS is used and no options are set",
      fn() {
        let options =
          connection.options()
          |> connection.with_transport(transport: connection.Tls)
          |> connection.options_to_ffi

        gun_secure_tls_summary("example.com", options)
        |> expect.to_equal(secure_tls_summary(
          server_name_indication: Some("example.com"),
          versions: default_versions(),
          depth: Some(10),
          has_cacerts: True,
          has_hostname_check: True,
        ))
      },
    ),

    startest.it("lets user-set TLS fields override the secure baseline", fn() {
      let tls_options =
        tls.options()
        |> tls.with_versions(versions: [tls.TlsV13])
        |> tls.with_depth(depth: 3)
        |> tls.with_server_name_indication(
          server_name_indication: tls.ServerName("override.example"),
        )

      let options =
        connection.options()
        |> connection.with_transport(transport: connection.Tls)
        |> connection.with_tls_options(tls_options)
        |> connection.options_to_ffi

      gun_secure_tls_summary("example.com", options)
      |> expect.to_equal(secure_tls_summary(
        server_name_indication: Some("override.example"),
        versions: Some(["tlsv1.3"]),
        depth: Some(3),
        has_cacerts: True,
        has_hostname_check: True,
      ))
    }),

    startest.it("tls.insecure() suppresses the secure baseline", fn() {
      let options =
        connection.options()
        |> connection.with_transport(transport: connection.Tls)
        |> connection.with_tls_options(tls.insecure())
        |> connection.options_to_ffi

      gun_secure_tls_summary("example.com", options)
      |> expect.to_equal(insecure_tls_summary())
    }),

    startest.it("skips SNI when host is an IP literal", fn() {
      let options =
        connection.options()
        |> connection.with_transport(transport: connection.Tls)
        |> connection.options_to_ffi

      gun_secure_tls_summary("127.0.0.1", options)
      |> expect.to_equal(secure_tls_summary(
        server_name_indication: None,
        versions: default_versions(),
        depth: Some(10),
        has_cacerts: True,
        has_hostname_check: True,
      ))
    }),

    startest.it("skips SNI when host is a bracketed IPv6 literal", fn() {
      let options =
        connection.options()
        |> connection.with_transport(transport: connection.Tls)
        |> connection.options_to_ffi

      gun_secure_tls_summary("[::1]", options)
      |> expect.to_equal(secure_tls_summary(
        server_name_indication: None,
        versions: default_versions(),
        depth: Some(10),
        has_cacerts: True,
        has_hostname_check: True,
      ))

      gun_secure_tls_summary("[2001:db8::1]", options)
      |> expect.to_equal(secure_tls_summary(
        server_name_indication: None,
        versions: default_versions(),
        depth: Some(10),
        has_cacerts: True,
        has_hostname_check: True,
      ))
    }),

    startest.it("applies the secure baseline for Auto transport too", fn() {
      let options =
        connection.options()
        |> connection.options_to_ffi

      gun_secure_tls_summary("example.com", options)
      |> expect.to_equal(secure_tls_summary(
        server_name_indication: Some("example.com"),
        versions: default_versions(),
        depth: Some(10),
        has_cacerts: True,
        has_hostname_check: True,
      ))
    }),

    startest.it("does not apply the secure baseline for TCP transport", fn() {
      let options =
        connection.options()
        |> connection.with_transport(transport: connection.Tcp)
        |> connection.options_to_ffi

      gun_secure_tls_summary("example.com", options)
      |> expect.to_equal(tls_summary(
        verify: None,
        versions: None,
        depth: None,
        server_name_indication: None,
        has_cacerts: False,
        has_hostname_check: False,
      ))
    }),

    startest.it(
      "returns InvalidOptions when secure defaults cannot load system CAs",
      fn() {
        let options =
          connection.options()
          |> connection.with_transport(transport: connection.Tls)
          |> connection.options_to_ffi

        gun_secure_tls_summary_with_empty_cacerts("example.com", options)
        |> expect.to_equal(
          Error(error.InvalidOptions("Tls(NoSystemCacerts(Empty))")),
        )
      },
    ),

    startest.it(
      "returns InvalidOptions when hostname match function is unavailable",
      fn() {
        let options =
          connection.options()
          |> connection.with_transport(transport: connection.Tls)
          |> connection.options_to_ffi

        gun_secure_tls_summary_with_hostname_match_failure(
          "example.com",
          options,
        )
        |> expect.to_equal(
          Error(error.InvalidOptions(
            "Tls(HostnameMatchFunUnavailable(Error(TestHostnameMatchFailure)))",
          )),
        )
      },
    ),

    startest.it(
      "caches system CA certificates after the first successful load",
      fn() {
        let options =
          connection.options()
          |> connection.with_transport(transport: connection.Tls)
          |> connection.options_to_ffi

        gun_secure_tls_cacerts_load_count("example.com", options)
        |> expect.to_equal(1)
      },
    ),
  ])
}

@external(erlang, "gluegun_ffi_test", "gun_tls_opts")
fn gun_tls_options(
  options: List(connection.ConnectOption),
) -> List(#(String, List(String)))

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
