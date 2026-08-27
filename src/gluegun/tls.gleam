//// Typed TLS client options for Gun and Erlang SSL.
////
//// Gluegun applies a secure baseline whenever a connection uses TLS
//// (`connection.Tls`, or `connection.Auto` resolving to TLS): peer and
//// hostname verification, system CA certificates, TLS 1.2/1.3, SNI for DNS
//// hosts, and HTTPS hostname matching. See the TLS guide for the canonical
//// default list and override behavior.
////
//// For development against self-signed endpoints, use `insecure()` —
//// it returns a `TlsOptions` that disables verification (and therefore
//// the rest of the secure baseline). Do **not** ship `insecure()` to
//// production.
////
//// ## Production HTTPS
////
//// The minimal HTTPS setup is just:
////
//// ```gleam
//// import gluegun/connection
////
//// pub fn https_options() {
////   connection.options()
////   |> connection.with_transport(transport: connection.Tls)
//// }
//// ```
////
//// Gluegun fills in `verify_peer`, the OS trust store, TLS 1.2/1.3, SNI,
//// and HTTPS hostname matching automatically when you call
//// `connection.open(host:, port:)`.
////
//// ## Overriding the baseline
////
//// ```gleam
//// import gluegun/connection
//// import gluegun/tls
////
//// pub fn https_options(host: String) {
////   let tls_opts =
////     tls.options()
////     |> tls.with_versions(versions: [tls.TlsV13])
////     |> tls.with_cacertfile(cacertfile: "/etc/ssl/cert.pem")
////     |> tls.with_depth(depth: 5)
////
////   connection.options()
////   |> connection.with_transport(transport: connection.Tls)
////   |> connection.with_tls_opts(tls_opts: tls_opts)
//// }
//// ```
////
//// Any field you set on `TlsOptions` overrides the corresponding default;
//// fields you leave unset are filled in by the secure baseline.

import gleam/option.{type Option, None, Some}

/// TLS peer verification mode.
pub type VerifyMode {
  /// Verify the peer certificate chain and hostname.
  VerifyPeer

  /// Disable peer certificate verification.
  VerifyNone
}

/// Supported TLS protocol versions.
pub type TlsVersion {
  /// Allow TLS 1.2.
  TlsV12

  /// Allow TLS 1.3.
  TlsV13
}

/// SNI configuration for a TLS connection.
pub type ServerNameIndication {
  /// Disable SNI for this connection.
  Disable

  /// Send the provided hostname as the SNI value.
  ServerName(String)
}

/// One Erlang SSL client option, encoded for the Gun FFI boundary.
///
/// `to_ffi` turns `TlsOptions` into a list of these settings.
/// `src/gluegun_ffi.erl` pattern matches each variant and builds the
/// corresponding `ssl:tls_client_option()` tuple, so option keys and values
/// stay typed on the Gleam side.
@internal
pub type TlsSetting {
  VerifySetting(VerifyMode)
  VersionsSetting(List(TlsVersion))
  CiphersSetting(List(String))
  CacertsSetting(List(BitArray))
  CacertfileSetting(String)
  CertfileSetting(String)
  KeyfileSetting(String)
  ServerNameIndicationSetting(ServerNameIndication)
  DepthSetting(Int)
}

/// Pure representation of TLS client options before FFI conversion.
///
/// Build with `options()` then chain `with_verify`, `with_versions`,
/// `with_ciphers`, `with_cacerts`, `with_cacertfile`, `with_certfile`,
/// `with_keyfile`, `with_server_name_indication`, and `with_depth`. See
/// [the TLS guide](https://gluegun.tylerbutler.com/guides/tls/) for a
/// production HTTPS baseline.
pub opaque type TlsOptions {
  TlsOptions(
    verify: Option(VerifyMode),
    versions: Option(List(TlsVersion)),
    ciphers: Option(List(String)),
    cacerts: Option(List(BitArray)),
    cacertfile: Option(String),
    certfile: Option(String),
    keyfile: Option(String),
    server_name_indication: Option(ServerNameIndication),
    depth: Option(Int),
  )
}

/// Construct empty TLS options.
pub fn options() -> TlsOptions {
  TlsOptions(
    verify: None,
    versions: None,
    ciphers: None,
    cacerts: None,
    cacertfile: None,
    certfile: None,
    keyfile: None,
    server_name_indication: None,
    depth: None,
  )
}

/// Construct TLS options that **disable** peer verification.
///
/// **Development only.** Returns options with `verify_none` and SNI
/// disabled, which suppresses Gluegun's secure TLS defaults (system CA
/// trust store, hostname verification, TLS 1.2/1.3 floor). This bypasses
/// the protections that make HTTPS trustworthy — never use it against
/// untrusted networks or production endpoints.
pub fn insecure() -> TlsOptions {
  options()
  |> with_verify(verify: VerifyNone)
  |> with_server_name_indication(server_name_indication: Disable)
}

/// Set the TLS peer verification mode.
pub fn with_verify(options: TlsOptions, verify verify: VerifyMode) -> TlsOptions {
  TlsOptions(..options, verify: Some(verify))
}

/// Set TLS protocol versions in preference order.
pub fn with_versions(
  options: TlsOptions,
  versions versions: List(TlsVersion),
) -> TlsOptions {
  TlsOptions(..options, versions: Some(versions))
}

/// Set TLS cipher suite names.
pub fn with_ciphers(
  options: TlsOptions,
  ciphers ciphers: List(String),
) -> TlsOptions {
  TlsOptions(..options, ciphers: Some(ciphers))
}

/// Set DER-encoded trusted CA certificates.
pub fn with_cacerts(
  options: TlsOptions,
  cacerts cacerts: List(BitArray),
) -> TlsOptions {
  TlsOptions(..options, cacerts: Some(cacerts))
}

/// Set the path to a PEM CA bundle file.
pub fn with_cacertfile(
  options: TlsOptions,
  cacertfile cacertfile: String,
) -> TlsOptions {
  TlsOptions(..options, cacertfile: Some(cacertfile))
}

/// Set the path to the client certificate file.
pub fn with_certfile(
  options: TlsOptions,
  certfile certfile: String,
) -> TlsOptions {
  TlsOptions(..options, certfile: Some(certfile))
}

/// Set the path to the client private key file.
pub fn with_keyfile(options: TlsOptions, keyfile keyfile: String) -> TlsOptions {
  TlsOptions(..options, keyfile: Some(keyfile))
}

/// Set the TLS SNI value, or disable it explicitly.
pub fn with_server_name_indication(
  options: TlsOptions,
  server_name_indication server_name_indication: ServerNameIndication,
) -> TlsOptions {
  TlsOptions(..options, server_name_indication: Some(server_name_indication))
}

/// Set the maximum certificate chain depth.
pub fn with_depth(options: TlsOptions, depth depth: Int) -> TlsOptions {
  TlsOptions(..options, depth: Some(depth))
}

/// Convert TLS options into the typed settings the Erlang FFI expects.
///
/// The returned list keeps Gun's expected option ordering: `verify` first,
/// then versions, ciphers, CA material, key material, SNI, and depth.
@internal
pub fn to_ffi(options: TlsOptions) -> List(TlsSetting) {
  []
  |> prepend_optional(options.depth, DepthSetting)
  |> prepend_optional(
    options.server_name_indication,
    ServerNameIndicationSetting,
  )
  |> prepend_optional(options.keyfile, KeyfileSetting)
  |> prepend_optional(options.certfile, CertfileSetting)
  |> prepend_optional(options.cacertfile, CacertfileSetting)
  |> prepend_optional(options.cacerts, CacertsSetting)
  |> prepend_optional(options.ciphers, CiphersSetting)
  |> prepend_optional(options.versions, VersionsSetting)
  |> prepend_optional(options.verify, VerifySetting)
}

fn prepend_optional(
  settings: List(TlsSetting),
  value: Option(value),
  encode: fn(value) -> TlsSetting,
) -> List(TlsSetting) {
  case value {
    Some(value) -> [encode(value), ..settings]
    None -> settings
  }
}
