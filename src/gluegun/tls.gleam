//// Typed TLS client options for Gun and Erlang SSL.
////
//// Gluegun keeps TLS configuration explicit instead of relying on Erlang's
//// historical defaults. Use this module to opt into peer verification, pin
//// TLS versions, configure CA bundles, or supply client certificate files.

import gleam/dynamic
import gleam/erlang/atom
import gleam/list
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

/// Pure representation of TLS client options before FFI conversion.
pub opaque type TlsOptions {
  TlsOptions(
    verify: Option(dynamic.Dynamic),
    versions: Option(List(TlsVersion)),
    ciphers: Option(List(String)),
    cacerts: Option(List(BitArray)),
    cacertfile: Option(String),
    certfile: Option(String),
    keyfile: Option(String),
    server_name_indication: Option(ServerNameIndication),
    depth: Option(Int),
    raw_options: List(#(String, dynamic.Dynamic)),
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
    raw_options: [],
  )
}

/// Set the TLS peer verification mode.
pub fn with_verify(options: TlsOptions, verify verify: VerifyMode) -> TlsOptions {
  TlsOptions(..options, verify: Some(verify_to_ffi(verify)))
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

/// Set the raw `verify` TLS option for uncommon Erlang SSL configurations.
///
/// Prefer `with_verify` for regular `verify_peer` or `verify_none` settings.
@internal
pub fn with_verify_dynamic(
  options: TlsOptions,
  verify verify: dynamic.Dynamic,
) -> TlsOptions {
  TlsOptions(..options, verify: Some(verify))
}

/// Append a raw Erlang SSL option for uncommon configurations.
///
/// This is intended for rare cases like `verify_fun` that do not yet have a
/// dedicated typed builder.
@internal
pub fn with_raw_option(
  options: TlsOptions,
  key key: String,
  value value: dynamic.Dynamic,
) -> TlsOptions {
  TlsOptions(..options, raw_options: [#(key, value), ..options.raw_options])
}

/// Convert TLS options to the Erlang FFI `ssl_options()` list shape.
@internal
pub fn to_ffi(options: TlsOptions) -> dynamic.Dynamic {
  let fields =
    []
    |> prepend_optional_int("depth", options.depth)
    |> prepend_optional_server_name_indication(options.server_name_indication)
    |> prepend_optional_string("keyfile", options.keyfile)
    |> prepend_optional_string("certfile", options.certfile)
    |> prepend_optional_string("cacertfile", options.cacertfile)
    |> prepend_optional_bit_arrays("cacerts", options.cacerts)
    |> prepend_optional_strings("ciphers", options.ciphers)
    |> prepend_optional_versions(options.versions)
    |> prepend_optional_dynamic("verify", options.verify)
    |> prepend_raw_options(list.reverse(options.raw_options))

  dynamic.list(fields)
}

fn prepend_optional_dynamic(
  fields: List(dynamic.Dynamic),
  key: String,
  value: Option(dynamic.Dynamic),
) -> List(dynamic.Dynamic) {
  case value {
    Some(value) -> [dynamic.array([atom_name(key), value]), ..fields]
    None -> fields
  }
}

fn prepend_optional_versions(
  fields: List(dynamic.Dynamic),
  versions: Option(List(TlsVersion)),
) -> List(dynamic.Dynamic) {
  case versions {
    Some(versions) -> [
      dynamic.array([
        atom_name("versions"),
        dynamic.list(list.map(versions, tls_version_to_ffi)),
      ]),
      ..fields
    ]
    None -> fields
  }
}

fn prepend_optional_strings(
  fields: List(dynamic.Dynamic),
  key: String,
  values: Option(List(String)),
) -> List(dynamic.Dynamic) {
  case values {
    Some(values) -> [
      dynamic.array([
        atom_name(key),
        dynamic.list(list.map(values, dynamic.string)),
      ]),
      ..fields
    ]
    None -> fields
  }
}

fn prepend_optional_bit_arrays(
  fields: List(dynamic.Dynamic),
  key: String,
  values: Option(List(BitArray)),
) -> List(dynamic.Dynamic) {
  case values {
    Some(values) -> [
      dynamic.array([
        atom_name(key),
        dynamic.list(list.map(values, dynamic.bit_array)),
      ]),
      ..fields
    ]
    None -> fields
  }
}

fn prepend_optional_string(
  fields: List(dynamic.Dynamic),
  key: String,
  value: Option(String),
) -> List(dynamic.Dynamic) {
  case value {
    Some(value) -> [
      dynamic.array([atom_name(key), dynamic.string(value)]),
      ..fields
    ]
    None -> fields
  }
}

fn prepend_optional_server_name_indication(
  fields: List(dynamic.Dynamic),
  server_name_indication: Option(ServerNameIndication),
) -> List(dynamic.Dynamic) {
  case server_name_indication {
    Some(server_name_indication) -> [
      dynamic.array([
        atom_name("server_name_indication"),
        server_name_indication_to_ffi(server_name_indication),
      ]),
      ..fields
    ]
    None -> fields
  }
}

fn prepend_optional_int(
  fields: List(dynamic.Dynamic),
  key: String,
  value: Option(Int),
) -> List(dynamic.Dynamic) {
  case value {
    Some(value) -> [
      dynamic.array([atom_name(key), dynamic.int(value)]),
      ..fields
    ]
    None -> fields
  }
}

fn prepend_raw_options(
  fields: List(dynamic.Dynamic),
  raw_options: List(#(String, dynamic.Dynamic)),
) -> List(dynamic.Dynamic) {
  list.append(
    fields,
    list.map(raw_options, fn(option) {
      dynamic.array([atom_name(option.0), option.1])
    }),
  )
}

fn atom_name(name: String) -> dynamic.Dynamic {
  atom.to_dynamic(atom.create(name))
}

fn verify_to_ffi(verify: VerifyMode) -> dynamic.Dynamic {
  case verify {
    VerifyPeer -> atom_name("verify_peer")
    VerifyNone -> atom_name("verify_none")
  }
}

fn tls_version_to_ffi(version: TlsVersion) -> dynamic.Dynamic {
  case version {
    TlsV12 -> atom_name("tlsv1.2")
    TlsV13 -> atom_name("tlsv1.3")
  }
}

fn server_name_indication_to_ffi(
  server_name_indication: ServerNameIndication,
) -> dynamic.Dynamic {
  case server_name_indication {
    Disable -> atom_name("disable")
    ServerName(hostname) -> dynamic.string(hostname)
  }
}
