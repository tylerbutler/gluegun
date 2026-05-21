import gleam/dict
import gleam/dynamic
import gleam/erlang/atom
import gluegun/connection
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

      gluegun_ffi_test_secure_tls_opts("example.com", opts)
      |> expect.to_equal(
        dict.from_list([
          #("verify", dynamic.string("verify_peer")),
          #(
            "versions",
            dynamic.list([dynamic.string("tlsv1.3"), dynamic.string("tlsv1.2")]),
          ),
          #("depth", dynamic.int(10)),
          #("sni", dynamic.string("example.com")),
          #("has_cacerts", dynamic.bool(True)),
          #("has_hostname_check", dynamic.bool(True)),
        ]),
      )
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

      gluegun_ffi_test_secure_tls_opts("example.com", opts)
      |> expect.to_equal(
        dict.from_list([
          #("verify", dynamic.string("verify_peer")),
          #("versions", dynamic.list([dynamic.string("tlsv1.3")])),
          #("depth", dynamic.int(3)),
          #("sni", dynamic.string("override.example")),
          #("has_cacerts", dynamic.bool(True)),
          #("has_hostname_check", dynamic.bool(True)),
        ]),
      )
    }),

    it("tls.insecure() suppresses the secure baseline", fn() {
      let opts =
        connection.options()
        |> connection.with_transport(transport: connection.Tls)
        |> connection.with_tls_opts(tls.insecure())
        |> connection.options_to_ffi

      gluegun_ffi_test_secure_tls_opts("example.com", opts)
      |> expect.to_equal(
        dict.from_list([
          #("verify", dynamic.string("verify_none")),
          #("versions", atom.to_dynamic(atom.create("undefined"))),
          #("depth", atom.to_dynamic(atom.create("undefined"))),
          #("sni", dynamic.string("disable")),
          #("has_cacerts", dynamic.bool(False)),
          #("has_hostname_check", dynamic.bool(False)),
        ]),
      )
    }),

    it("skips SNI when host is an IP literal", fn() {
      let opts =
        connection.options()
        |> connection.with_transport(transport: connection.Tls)
        |> connection.options_to_ffi

      gluegun_ffi_test_secure_tls_opts("127.0.0.1", opts)
      |> expect.to_equal(
        dict.from_list([
          #("verify", dynamic.string("verify_peer")),
          #(
            "versions",
            dynamic.list([dynamic.string("tlsv1.3"), dynamic.string("tlsv1.2")]),
          ),
          #("depth", dynamic.int(10)),
          #("sni", atom.to_dynamic(atom.create("undefined"))),
          #("has_cacerts", dynamic.bool(True)),
          #("has_hostname_check", dynamic.bool(True)),
        ]),
      )
    }),

    it("applies the secure baseline for Auto transport too", fn() {
      let opts =
        connection.options()
        |> connection.options_to_ffi

      gluegun_ffi_test_secure_tls_opts("example.com", opts)
      |> expect.to_equal(
        dict.from_list([
          #("verify", dynamic.string("verify_peer")),
          #(
            "versions",
            dynamic.list([dynamic.string("tlsv1.3"), dynamic.string("tlsv1.2")]),
          ),
          #("depth", dynamic.int(10)),
          #("sni", dynamic.string("example.com")),
          #("has_cacerts", dynamic.bool(True)),
          #("has_hostname_check", dynamic.bool(True)),
        ]),
      )
    }),

    it("does not apply the secure baseline for TCP transport", fn() {
      let opts =
        connection.options()
        |> connection.with_transport(transport: connection.Tcp)
        |> connection.options_to_ffi

      gluegun_ffi_test_secure_tls_opts("example.com", opts)
      |> expect.to_equal(
        dict.from_list([
          #("verify", atom.to_dynamic(atom.create("undefined"))),
          #("versions", atom.to_dynamic(atom.create("undefined"))),
          #("depth", atom.to_dynamic(atom.create("undefined"))),
          #("sni", atom.to_dynamic(atom.create("undefined"))),
          #("has_cacerts", dynamic.bool(False)),
          #("has_hostname_check", dynamic.bool(False)),
        ]),
      )
    }),
  ])
}

@external(erlang, "gluegun_ffi_test", "gun_tls_opts")
fn gluegun_ffi_test_gun_tls_opts(options: dynamic.Dynamic) -> dynamic.Dynamic

@external(erlang, "gluegun_ffi_test", "secure_tls_opts")
fn gluegun_ffi_test_secure_tls_opts(
  host: String,
  options: dynamic.Dynamic,
) -> dict.Dict(String, dynamic.Dynamic)
