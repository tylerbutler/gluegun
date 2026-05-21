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
  ])
}

@external(erlang, "gluegun_ffi_test", "gun_tls_opts")
fn gluegun_ffi_test_gun_tls_opts(options: dynamic.Dynamic) -> dynamic.Dynamic
