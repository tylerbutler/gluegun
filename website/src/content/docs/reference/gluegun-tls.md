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

- `Disable()`
- `ServerName(String)`

### `TlsOptions`

Pure representation of TLS client options before FFI conversion.

 Build with `options()` then chain `with_verify`, `with_versions`,
 `with_ciphers`, `with_cacerts`, `with_cacertfile`, `with_certfile`,
 `with_keyfile`, `with_server_name_indication`, and `with_depth`. See
 [the TLS guide](https://gluegun.tylerbutler.com/guides/tls/) for a
 production HTTPS baseline.



### `TlsVersion`

Supported TLS protocol versions.

- `TlsV12()`
- `TlsV13()`

### `VerifyMode`

TLS peer verification mode.

- `VerifyPeer()`
- `VerifyNone()`

## Functions

### `options`

Construct empty TLS options.

```gleam
pub fn options() -> gluegun/tls.TlsOptions
```

### `with_cacertfile`

Set the path to a PEM CA bundle file.

```gleam
pub fn with_cacertfile(gluegun/tls.TlsOptions, cacertfile: String) -> gluegun/tls.TlsOptions
```

### `with_cacerts`

Set DER-encoded trusted CA certificates.

```gleam
pub fn with_cacerts(gluegun/tls.TlsOptions, cacerts: List(BitArray)) -> gluegun/tls.TlsOptions
```

### `with_certfile`

Set the path to the client certificate file.

```gleam
pub fn with_certfile(gluegun/tls.TlsOptions, certfile: String) -> gluegun/tls.TlsOptions
```

### `with_ciphers`

Set TLS cipher suite names.

```gleam
pub fn with_ciphers(gluegun/tls.TlsOptions, ciphers: List(String)) -> gluegun/tls.TlsOptions
```

### `with_depth`

Set the maximum certificate chain depth.

```gleam
pub fn with_depth(gluegun/tls.TlsOptions, depth: Int) -> gluegun/tls.TlsOptions
```

### `with_keyfile`

Set the path to the client private key file.

```gleam
pub fn with_keyfile(gluegun/tls.TlsOptions, keyfile: String) -> gluegun/tls.TlsOptions
```

### `with_server_name_indication`

Set the TLS SNI value, or disable it explicitly.

```gleam
pub fn with_server_name_indication(gluegun/tls.TlsOptions, server_name_indication: gluegun/tls.ServerNameIndication) -> gluegun/tls.TlsOptions
```

### `with_verify`

Set the TLS peer verification mode.

```gleam
pub fn with_verify(gluegun/tls.TlsOptions, verify: gluegun/tls.VerifyMode) -> gluegun/tls.TlsOptions
```

### `with_versions`

Set TLS protocol versions in preference order.

```gleam
pub fn with_versions(gluegun/tls.TlsOptions, versions: List(gluegun/tls.TlsVersion)) -> gluegun/tls.TlsOptions
```
