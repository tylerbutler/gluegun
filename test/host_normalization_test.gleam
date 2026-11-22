import gleam/http
import gleam/int
import gluegun/connection
import gluegun/error
import gluegun/message
import gluegun/request
import gluegun/tls

pub fn ipv4_uses_a_tuple_without_numeric_sni_test() -> Nil {
  succeeds(
    "127.0.0.1",
    connection.Ipv4,
    True,
    tls.options(),
    "127.0.0.1",
    True,
    Error(Nil),
  )
}

pub fn ipv6_uses_a_tuple_and_bracketed_wire_authority_test() -> Nil {
  succeeds("::1", connection.Ipv6, True, tls.options(), "::1", True, Error(Nil))
}

pub fn bracketed_ipv6_uses_a_tuple_and_single_brackets_on_wire_test() -> Nil {
  succeeds(
    "[::1]",
    connection.Ipv6,
    True,
    tls.options(),
    "::1",
    True,
    Error(Nil),
  )
}

pub fn ipv4_rejects_a_trusted_certificate_for_a_different_ip_test() -> Nil {
  rejects("127.0.0.1", connection.Ipv4, tls.options())
}

pub fn ipv6_rejects_a_trusted_certificate_for_a_different_ip_test() -> Nil {
  rejects("[::1]", connection.Ipv6, tls.options())
}

pub fn absolute_dns_keeps_lookup_spelling_but_derives_unrooted_sni_test() -> Nil {
  succeeds(
    "LoCaLhOsT.",
    connection.Ipv4,
    True,
    tls.options(),
    "LoCaLhOsT.",
    False,
    Ok("LoCaLhOsT"),
  )
}

pub fn explicit_dns_sni_keeps_its_terminal_dot_test() -> Nil {
  explicit_rooted_sni("localhost.")
}

pub fn explicit_sni_on_ip_keeps_its_terminal_dot_test() -> Nil {
  explicit_rooted_sni("127.0.0.1")
}

fn explicit_rooted_sni(host: String) -> Nil {
  let assert Ok(Nil) =
    with_client_hello(fn(port, peer) {
      let assert Ok(connection) =
        options(
          connection.Ipv4,
          tls.options()
            |> tls.with_server_name_indication(tls.ServerName(
              "override.localhost.",
            )),
        )
        |> connection.open(host: host, port: port)
      with_connection(connection, fn() {
        // Inspect the final TLS ClientHello, since OTP servers reject rooted
        // SNI. Verification remains enabled; do not complete this handshake.
        let assert Ok("override.localhost.") = client_hello_sni(peer)
        Ok(Nil)
      })
    })
  Nil
}

pub fn explicit_sni_overrides_ip_certificate_identity_test() -> Nil {
  succeeds(
    "[::1]",
    connection.Ipv6,
    False,
    tls.options()
      |> tls.with_server_name_indication(tls.ServerName("localhost")),
    "::1",
    True,
    Ok("localhost"),
  )
}

pub fn explicit_mismatching_sni_on_ip_still_rejects_the_peer_test() -> Nil {
  rejects(
    "127.0.0.1",
    connection.Ipv4,
    tls.options()
      |> tls.with_server_name_indication(tls.ServerName("wrong.invalid")),
  )
}

fn succeeds(
  host: String,
  family: connection.AddressFamily,
  matching: Bool,
  settings: tls.TlsOptions,
  origin: String,
  is_ip: Bool,
  sni: Result(String, Nil),
) -> Nil {
  let assert Ok(Nil) =
    with_host_peer(family, matching, fn(port, certificates, peer) {
      let assert Ok(connection) =
        options(family, settings |> tls.with_cacerts(certificates))
        |> connection.open(host: host, port: port)
      with_connection(connection, fn() {
        let assert Ok(connection.Http1) =
          connection.await_up(connection, timeout())
        let actual = tls_identity(connection)
        let expected = #(origin, is_ip, sni, True)
        let assert #(True, _, _) = #(actual == expected, actual, expected)
        let assert Ok(stream) =
          request.request(
            connection,
            http.Get,
            "/",
            [],
            <<>>,
            request.options(),
          )
        let assert Ok(#(authority, observed_sni)) = peer_request(peer)
        let wire_host = case family, is_ip {
          connection.Ipv6, True -> "[::1]"
          connection.Ipv4, True -> "127.0.0.1"
          connection.Ipv4, False | connection.Ipv6, False -> host
        }
        let assert True = authority == wire_host <> ":" <> int.to_string(port)
        let assert True = observed_sni == sni
        let assert Ok(message.Response(_, 200, _)) =
          message.await(connection, stream, timeout())
        Ok(Nil)
      })
    })
  Nil
}

fn rejects(
  host: String,
  family: connection.AddressFamily,
  settings: tls.TlsOptions,
) -> Nil {
  let assert Ok(Nil) =
    with_host_peer(family, False, fn(port, certificates, _peer) {
      let assert Ok(connection) =
        options(family, settings |> tls.with_cacerts(certificates))
        |> connection.open(host: host, port: port)
      with_connection(connection, fn() {
        // A DNS/setup failure is not evidence that IP identity was checked.
        let actual = await_identity_failure(connection)
        let assert #(True, _) = #(actual == Ok(Nil), actual)
        Ok(Nil)
      })
    })
  Nil
}

fn options(
  family: connection.AddressFamily,
  settings: tls.TlsOptions,
) -> connection.ConnectOptions {
  connection.options()
  |> connection.with_transport(connection.Tls)
  |> connection.with_protocols([connection.Http1])
  |> connection.with_address_family(family)
  |> connection.with_connect_timeout(timeout())
  |> connection.with_tls_handshake_timeout(timeout())
  |> connection.with_tls_options(settings)
}

fn timeout() -> connection.Timeout {
  let assert Ok(timeout) = connection.milliseconds(2000)
  timeout
}

type HostPeer

@external(erlang, "gluegun_bounded_test", "with_host_peer")
fn with_host_peer(
  family: connection.AddressFamily,
  matching: Bool,
  callback: fn(Int, List(BitArray), HostPeer) -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_bounded_test", "peer_request")
fn peer_request(
  peer: HostPeer,
) -> Result(#(String, Result(String, Nil)), String)

@external(erlang, "gluegun_bounded_test", "tls_identity")
fn tls_identity(
  connection: connection.Connection,
) -> #(String, Bool, Result(String, Nil), Bool)

@external(erlang, "gluegun_runtime_regression_test", "with_connection")
fn with_connection(
  connection: connection.Connection,
  callback: fn() -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_bounded_test", "await_identity_failure")
fn await_identity_failure(
  connection: connection.Connection,
) -> Result(Nil, String)

@external(erlang, "gluegun_bounded_test", "with_client_hello")
fn with_client_hello(
  callback: fn(Int, HostPeer) -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_bounded_test", "client_hello_sni")
fn client_hello_sni(peer: HostPeer) -> Result(String, String)
