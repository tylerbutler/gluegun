import gleam/dict
import gleam/dynamic
import gleam/erlang/atom
import gleam/result
import gluegun/connection
import gluegun/error
import gluegun/tls
import startest.{describe, it}
import startest/expect

pub fn tls_tests() {
  describe("TLS option encoding", [
    it("nests TLS options under transport_opts in connection FFI", fn() {
      let options =
        connection.options()
        |> connection.with_transport(transport: connection.Tls)
        |> connection.with_tls_opts(
          tls.options()
          |> tls.with_verify(verify: tls.VerifyPeer)
          |> tls.with_versions(versions: [tls.TlsV12, tls.TlsV13]),
        )

      connection.options_to_ffi(options)
      |> expect.to_equal(
        dynamic.properties([
          #(dynamic.string("transport"), atom.to_dynamic(atom.create("tls"))),
          #(dynamic.string("retry"), dynamic.int(5000)),
          #(dynamic.string("connect_timeout"), dynamic.int(5000)),
          #(
            dynamic.string("transport_opts"),
            dynamic.properties([
              #(
                dynamic.string("tls_opts"),
                dynamic.list([
                  dynamic.array([
                    atom.to_dynamic(atom.create("verify")),
                    atom.to_dynamic(atom.create("verify_peer")),
                  ]),
                  dynamic.array([
                    atom.to_dynamic(atom.create("versions")),
                    dynamic.list([
                      atom.to_dynamic(atom.create("tlsv1.2")),
                      atom.to_dynamic(atom.create("tlsv1.3")),
                    ]),
                  ]),
                ]),
              ),
            ]),
          ),
        ]),
      )
    }),

    it("converts nested TLS options to Gun tls_opts", fn() {
      let tls_options =
        tls.options()
        |> tls.with_verify(verify: tls.VerifyPeer)
        |> tls.with_versions(versions: [tls.TlsV12, tls.TlsV13])

      connection.options()
      |> connection.with_transport(transport: connection.Tls)
      |> connection.with_tls_opts(tls_options)
      |> connection.options_to_ffi
      |> gluegun_ffi_test_gun_tls_opts
      |> expect.to_equal(
        dynamic.list([
          dynamic.array([
            atom.to_dynamic(atom.create("verify")),
            atom.to_dynamic(atom.create("verify_peer")),
          ]),
          dynamic.array([
            atom.to_dynamic(atom.create("versions")),
            dynamic.list([
              atom.to_dynamic(atom.create("tlsv1.2")),
              atom.to_dynamic(atom.create("tlsv1.3")),
            ]),
          ]),
        ]),
      )
    }),

    it("includes TLS options for auto transport", fn() {
      let tls_options = tls.options() |> tls.with_verify(verify: tls.VerifyPeer)

      connection.options()
      |> connection.with_tls_opts(tls_options)
      |> connection.options_to_ffi
      |> expect.to_equal(
        dynamic.properties([
          #(dynamic.string("transport"), atom.to_dynamic(atom.create("auto"))),
          #(dynamic.string("retry"), dynamic.int(5000)),
          #(dynamic.string("connect_timeout"), dynamic.int(5000)),
          #(
            dynamic.string("transport_opts"),
            dynamic.properties([
              #(
                dynamic.string("tls_opts"),
                dynamic.list([
                  dynamic.array([
                    atom.to_dynamic(atom.create("verify")),
                    atom.to_dynamic(atom.create("verify_peer")),
                  ]),
                ]),
              ),
            ]),
          ),
        ]),
      )
    }),

    it("skips TLS transport options for TCP connections", fn() {
      let tls_options = tls.options() |> tls.with_verify(verify: tls.VerifyPeer)

      connection.options()
      |> connection.with_transport(transport: connection.Tcp)
      |> connection.with_tls_opts(tls_options)
      |> connection.options_to_ffi
      |> expect.to_equal(
        dynamic.properties([
          #(dynamic.string("transport"), atom.to_dynamic(atom.create("tcp"))),
          #(dynamic.string("retry"), dynamic.int(5000)),
          #(dynamic.string("connect_timeout"), dynamic.int(5000)),
        ]),
      )
    }),

    it("applies the secure baseline when TLS is used and no opts are set", fn() {
      let opts =
        connection.options()
        |> connection.with_transport(transport: connection.Tls)
        |> connection.options_to_ffi

      gluegun_ffi_test_secure_tls_opts_summary("example.com", opts)
      |> expect.to_equal(secure_tls_summary(
        sni: dynamic.string("example.com"),
        versions: default_versions(),
        depth: dynamic.int(10),
        has_cacerts: True,
        has_hostname_check: True,
      ))
    }),

    it("lets user-set TLS fields override the secure baseline", fn() {
      let tls_options =
        tls.options()
        |> tls.with_versions(versions: [tls.TlsV13])
        |> tls.with_depth(depth: 3)
        |> tls.with_server_name_indication(
          server_name_indication: tls.ServerName("override.example"),
        )

      let opts =
        connection.options()
        |> connection.with_transport(transport: connection.Tls)
        |> connection.with_tls_opts(tls_options)
        |> connection.options_to_ffi

      gluegun_ffi_test_secure_tls_opts_summary("example.com", opts)
      |> expect.to_equal(secure_tls_summary(
        sni: dynamic.string("override.example"),
        versions: dynamic.list([dynamic.string("tlsv1.3")]),
        depth: dynamic.int(3),
        has_cacerts: True,
        has_hostname_check: True,
      ))
    }),

    it("tls.insecure() suppresses the secure baseline", fn() {
      let opts =
        connection.options()
        |> connection.with_transport(transport: connection.Tls)
        |> connection.with_tls_opts(tls.insecure())
        |> connection.options_to_ffi

      gluegun_ffi_test_secure_tls_opts_summary("example.com", opts)
      |> expect.to_equal(insecure_tls_summary())
    }),

    it("skips SNI when host is an IP literal", fn() {
      let opts =
        connection.options()
        |> connection.with_transport(transport: connection.Tls)
        |> connection.options_to_ffi

      gluegun_ffi_test_secure_tls_opts_summary("127.0.0.1", opts)
      |> expect.to_equal(secure_tls_summary(
        sni: undefined_dynamic(),
        versions: default_versions(),
        depth: dynamic.int(10),
        has_cacerts: True,
        has_hostname_check: True,
      ))
    }),

    it("skips SNI when host is a bracketed IPv6 literal", fn() {
      let opts =
        connection.options()
        |> connection.with_transport(transport: connection.Tls)
        |> connection.options_to_ffi

      gluegun_ffi_test_secure_tls_opts_summary("[::1]", opts)
      |> expect.to_equal(secure_tls_summary(
        sni: undefined_dynamic(),
        versions: default_versions(),
        depth: dynamic.int(10),
        has_cacerts: True,
        has_hostname_check: True,
      ))

      gluegun_ffi_test_secure_tls_opts_summary("[2001:db8::1]", opts)
      |> expect.to_equal(secure_tls_summary(
        sni: undefined_dynamic(),
        versions: default_versions(),
        depth: dynamic.int(10),
        has_cacerts: True,
        has_hostname_check: True,
      ))
    }),

    it("applies the secure baseline for Auto transport too", fn() {
      let opts =
        connection.options()
        |> connection.options_to_ffi

      gluegun_ffi_test_secure_tls_opts_summary("example.com", opts)
      |> expect.to_equal(secure_tls_summary(
        sni: dynamic.string("example.com"),
        versions: default_versions(),
        depth: dynamic.int(10),
        has_cacerts: True,
        has_hostname_check: True,
      ))
    }),

    it("does not apply the secure baseline for TCP transport", fn() {
      let opts =
        connection.options()
        |> connection.with_transport(transport: connection.Tcp)
        |> connection.options_to_ffi

      gluegun_ffi_test_secure_tls_opts_summary("example.com", opts)
      |> expect.to_equal(tls_summary(
        verify: undefined_dynamic(),
        versions: undefined_dynamic(),
        depth: undefined_dynamic(),
        sni: undefined_dynamic(),
        has_cacerts: False,
        has_hostname_check: False,
      ))
    }),

    it(
      "returns InvalidOptions when secure defaults cannot load system CAs",
      fn() {
        let opts =
          connection.options()
          |> connection.with_transport(transport: connection.Tls)
          |> connection.options_to_ffi

        gluegun_ffi_test_secure_tls_opts_with_empty_cacerts("example.com", opts)
        |> result.map_error(error.decode_ffi_error)
        |> expect.to_equal(
          Error(error.InvalidOptions("Tls(NoSystemCacerts(Empty))")),
        )
      },
    ),

    it(
      "returns InvalidOptions when hostname match function is unavailable",
      fn() {
        let opts =
          connection.options()
          |> connection.with_transport(transport: connection.Tls)
          |> connection.options_to_ffi

        gluegun_ffi_test_secure_tls_opts_with_hostname_match_failure(
          "example.com",
          opts,
        )
        |> result.map_error(error.decode_ffi_error)
        |> expect.to_equal(
          Error(error.InvalidOptions(
            "Tls(HostnameMatchFunUnavailable(Error(TestHostnameMatchFailure)))",
          )),
        )
      },
    ),

    it("caches system CA certificates after the first successful load", fn() {
      let opts =
        connection.options()
        |> connection.with_transport(transport: connection.Tls)
        |> connection.options_to_ffi

      gluegun_ffi_test_secure_tls_opts_caches_cacerts("example.com", opts)
      |> expect.to_equal(1)
    }),
  ])
}

@external(erlang, "gluegun_ffi_test", "gun_tls_opts")
fn gluegun_ffi_test_gun_tls_opts(options: dynamic.Dynamic) -> dynamic.Dynamic

@external(erlang, "gluegun_ffi_test", "secure_tls_opts_summary")
fn gluegun_ffi_test_secure_tls_opts_summary(
  host: String,
  options: dynamic.Dynamic,
) -> dict.Dict(String, dynamic.Dynamic)

@external(erlang, "gluegun_ffi_test", "secure_tls_opts_with_empty_cacerts")
fn gluegun_ffi_test_secure_tls_opts_with_empty_cacerts(
  host: String,
  options: dynamic.Dynamic,
) -> Result(dict.Dict(String, dynamic.Dynamic), dynamic.Dynamic)

@external(erlang, "gluegun_ffi_test", "secure_tls_opts_with_hostname_match_failure")
fn gluegun_ffi_test_secure_tls_opts_with_hostname_match_failure(
  host: String,
  options: dynamic.Dynamic,
) -> Result(dict.Dict(String, dynamic.Dynamic), dynamic.Dynamic)

@external(erlang, "gluegun_ffi_test", "secure_tls_opts_caches_cacerts")
fn gluegun_ffi_test_secure_tls_opts_caches_cacerts(
  host: String,
  options: dynamic.Dynamic,
) -> Int

fn secure_tls_summary(
  sni sni: dynamic.Dynamic,
  versions versions: dynamic.Dynamic,
  depth depth: dynamic.Dynamic,
  has_cacerts has_cacerts: Bool,
  has_hostname_check has_hostname_check: Bool,
) {
  tls_summary(
    verify: dynamic.string("verify_peer"),
    versions: versions,
    depth: depth,
    sni: sni,
    has_cacerts: has_cacerts,
    has_hostname_check: has_hostname_check,
  )
}

fn insecure_tls_summary() {
  tls_summary(
    verify: dynamic.string("verify_none"),
    versions: undefined_dynamic(),
    depth: undefined_dynamic(),
    sni: dynamic.string("disable"),
    has_cacerts: False,
    has_hostname_check: False,
  )
}

fn tls_summary(
  verify verify: dynamic.Dynamic,
  versions versions: dynamic.Dynamic,
  depth depth: dynamic.Dynamic,
  sni sni: dynamic.Dynamic,
  has_cacerts has_cacerts: Bool,
  has_hostname_check has_hostname_check: Bool,
) {
  dict.from_list([
    #("verify", verify),
    #("versions", versions),
    #("depth", depth),
    #("sni", sni),
    #("has_cacerts", dynamic.bool(has_cacerts)),
    #("has_hostname_check", dynamic.bool(has_hostname_check)),
  ])
}

fn default_versions() {
  dynamic.list([dynamic.string("tlsv1.3"), dynamic.string("tlsv1.2")])
}

fn undefined_dynamic() {
  atom.to_dynamic(atom.create("undefined"))
}
