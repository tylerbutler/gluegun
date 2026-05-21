---
title: gluegun/tls
description: Typed TLS client options for Gun and Erlang SSL.
---

# `gluegun/tls`

Typed TLS client options for Gun and Erlang SSL.

 Gluegun keeps TLS configuration explicit instead of relying on Erlang's
 historical defaults. Use this module to opt into peer verification, pin
 TLS versions, configure CA bundles, or supply client certificate files.

 ## Production HTTPS baseline

 ```gleam
 import gluegun/connection
 import gluegun/tls

 pub fn https_options(host: String) {
   let tls_opts =
     tls.options()
     |> tls.with_verify(verify: tls.VerifyPeer)
     |> tls.with_versions(versions: [tls.TlsV13, tls.TlsV12])
     |> tls.with_cacertfile(cacertfile: "/etc/ssl/cert.pem")
     |> tls.with_server_name_indication(
       server_name_indication: tls.ServerName(host),
     )
     |> tls.with_depth(depth: 10)

   connection.options()
   |> connection.with_transport(transport: connection.Tls)
   |> connection.with_tls_opts(tls_opts: tls_opts)
 }
 ```

 `VerifyPeer` enables certificate chain *and* hostname verification.
 `with_server_name_indication` sets the SNI value sent in the TLS
 ClientHello; hostname verification itself requires `VerifyPeer` plus
 trusted CA material (`with_cacerts` or `with_cacertfile`).

## Types

### `ServerNameIndication`

SNI configuration for a TLS connection.

```gleam
pub type ServerNameIndication {
  Disable
  ServerName(String)
}
```

**Constructors**

#### `Disable`

Disable SNI for this connection.

#### `ServerName(String)`

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

**Constructors**

#### `TlsV12`

Allow TLS 1.2.

#### `TlsV13`

Allow TLS 1.3.

### `VerifyMode`

TLS peer verification mode.

```gleam
pub type VerifyMode {
  VerifyPeer
  VerifyNone
}
```

**Constructors**

#### `VerifyPeer`

Verify the peer certificate chain and hostname.

#### `VerifyNone`

Disable peer certificate verification.

## Functions

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
