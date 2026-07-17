---
title: gluegun/tls
description: Typed TLS client options for Gun and Erlang SSL.
---

Typed TLS client options for Gun and Erlang SSL.

 Gluegun applies a secure baseline whenever a connection uses TLS
 (`connection.Tls`, or `connection.Auto` resolving to TLS): peer and
 hostname verification, system CA certificates, TLS 1.2/1.3, SNI for DNS
 hosts, and HTTPS hostname matching. See the TLS guide for the canonical
 default list and override behavior.

 For development against self-signed endpoints, use `insecure()` —
 it returns a `TlsOptions` that disables verification (and therefore
 the rest of the secure baseline). Do **not** ship `insecure()` to
 production.

 ## Production HTTPS

 The minimal HTTPS setup is just:

 ```gleam
 import gluegun/connection

 pub fn https_options() {
   connection.options()
   |> connection.with_transport(transport: connection.Tls)
 }
 ```

 Gluegun fills in `verify_peer`, the OS trust store, TLS 1.2/1.3, SNI,
 and HTTPS hostname matching automatically when you call
 `connection.open(host:, port:)`.

 ## Overriding the baseline

 ```gleam
 import gluegun/connection
 import gluegun/tls

 pub fn https_options(host: String) {
   let tls_opts =
     tls.options()
     |> tls.with_versions(versions: [tls.TlsV13])
     |> tls.with_cacertfile(cacertfile: "/etc/ssl/cert.pem")
     |> tls.with_depth(depth: 5)

   connection.options()
   |> connection.with_transport(transport: connection.Tls)
   |> connection.with_tls_opts(tls_opts: tls_opts)
 }
 ```

 Any field you set on `TlsOptions` overrides the corresponding default;
 fields you leave unset are filled in by the secure baseline.

## Types

### `ServerNameIndication`

SNI configuration for a TLS connection.

```gleam
pub type ServerNameIndication {
  Disable
  ServerName(String)
}
```

#### Constructors

##### `Disable`

Disable SNI for this connection.

##### `ServerName(String)`

Send the provided hostname as the SNI value.

### `TlsOptions`

Pure representation of TLS client options before FFI conversion.

 Build with `options()` then chain `with_verify`, `with_versions`,
 `with_ciphers`, `with_cacerts`, `with_cacertfile`, `with_certfile`,
 `with_keyfile`, `with_server_name_indication`, and `with_depth`. See
 [the TLS guide](https://gluegun.tylerbutler.com/guides/tls/) for a
 production HTTPS baseline.

```gleam
pub type TlsOptions
```

### `TlsVersion`

Supported TLS protocol versions.

```gleam
pub type TlsVersion {
  TlsV12
  TlsV13
}
```

#### Constructors

##### `TlsV12`

Allow TLS 1.2.

##### `TlsV13`

Allow TLS 1.3.

### `VerifyMode`

TLS peer verification mode.

```gleam
pub type VerifyMode {
  VerifyPeer
  VerifyNone
}
```

#### Constructors

##### `VerifyPeer`

Verify the peer certificate chain and hostname.

##### `VerifyNone`

Disable peer certificate verification.

## Functions

### `insecure`

Construct TLS options that **disable** peer verification.

 **Development only.** Returns options with `verify_none` and SNI
 disabled, which suppresses Gluegun's secure TLS defaults (system CA
 trust store, hostname verification, TLS 1.2/1.3 floor). This bypasses
 the protections that make HTTPS trustworthy — never use it against
 untrusted networks or production endpoints.

```gleam
pub fn insecure() -> TlsOptions
```

### `options`

Construct empty TLS options.

```gleam
pub fn options() -> TlsOptions
```

### `with_cacertfile`

Set the path to a PEM CA bundle file.

```gleam
pub fn with_cacertfile(
  TlsOptions,
  cacertfile: String
) -> TlsOptions
```

### `with_cacerts`

Set DER-encoded trusted CA certificates.

```gleam
pub fn with_cacerts(
  TlsOptions,
  cacerts: List(BitArray)
) -> TlsOptions
```

### `with_certfile`

Set the path to the client certificate file.

```gleam
pub fn with_certfile(
  TlsOptions,
  certfile: String
) -> TlsOptions
```

### `with_ciphers`

Set TLS cipher suite names.

```gleam
pub fn with_ciphers(
  TlsOptions,
  ciphers: List(String)
) -> TlsOptions
```

### `with_depth`

Set the maximum certificate chain depth.

```gleam
pub fn with_depth(
  TlsOptions,
  depth: Int
) -> TlsOptions
```

### `with_keyfile`

Set the path to the client private key file.

```gleam
pub fn with_keyfile(
  TlsOptions,
  keyfile: String
) -> TlsOptions
```

### `with_server_name_indication`

Set the TLS SNI value, or disable it explicitly.

```gleam
pub fn with_server_name_indication(
  TlsOptions,
  server_name_indication: ServerNameIndication
) -> TlsOptions
```

### `with_verify`

Set the TLS peer verification mode.

```gleam
pub fn with_verify(
  TlsOptions,
  verify: VerifyMode
) -> TlsOptions
```

### `with_versions`

Set TLS protocol versions in preference order.

```gleam
pub fn with_versions(
  TlsOptions,
  versions: List(TlsVersion)
) -> TlsOptions
```
