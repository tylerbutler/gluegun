---
title: TLS
description: Configure peer verification, CA bundles, TLS versions, and client certificates.
---

Gluegun exposes Erlang SSL client options through `gluegun/tls`.

## Security default

Gluegun does **not** enable peer verification by default. This follows Gun and Erlang SSL's historical default of `verify_none` for backward compatibility.

For production TLS connections, set `tls.with_verify(verify: tls.VerifyPeer)`, provide trusted CA certificates, and set `tls.with_server_name_indication` to the hostname you expect. `VerifyPeer` validates the certificate chain; SNI is what enables hostname verification too.

## Recommended production baseline

This example enables peer verification, keeps TLS 1.2 and 1.3, and sends SNI for the target hostname.

```gleam
import gluegun/connection
import gluegun/tls

pub fn secure_options() {
  let tls_options =
    tls.options()
    |> tls.with_verify(verify: tls.VerifyPeer)
    |> tls.with_versions(versions: [tls.TlsV12, tls.TlsV13])
    |> tls.with_server_name_indication(
      server_name_indication: tls.ServerName("example.com"),
    )
    |> tls.with_cacerts(cacerts: system_cacerts())

  connection.options()
  |> connection.with_transport(transport: connection.Tls)
  |> connection.with_tls_opts(tls_opts: tls_options)
}

@external(erlang, "public_key", "cacerts_get")
fn system_cacerts() -> List(BitArray)
```

`public_key:cacerts_get/0` is available on OTP 25 and newer. It returns the system CA certificates as DER-encoded binaries, which map directly to `tls.with_cacerts`.

If you cannot use `cacerts_get/0`, point at a PEM bundle file instead:

```gleam
let tls_options =
  tls.options()
  |> tls.with_verify(verify: tls.VerifyPeer)
  |> tls.with_server_name_indication(
    server_name_indication: tls.ServerName("example.com"),
  )
  |> tls.with_cacertfile(cacertfile: "/etc/ssl/certs/ca-certificates.crt")
```

## TLS 1.2 minimum

To require TLS 1.2 or newer, set the allowed versions explicitly:

```gleam
let tls_options =
  tls.options()
  |> tls.with_verify(verify: tls.VerifyPeer)
  |> tls.with_server_name_indication(
    server_name_indication: tls.ServerName("example.com"),
  )
  |> tls.with_versions(versions: [tls.TlsV12, tls.TlsV13])
```

## Client certificate authentication

Use `certfile` and `keyfile` when the server requires mTLS:

```gleam
let tls_options =
  tls.options()
  |> tls.with_verify(verify: tls.VerifyPeer)
  |> tls.with_server_name_indication(
    server_name_indication: tls.ServerName("mtls.example.com"),
  )
  |> tls.with_cacertfile(cacertfile: "./certs/ca.pem")
  |> tls.with_certfile(certfile: "./certs/client.pem")
  |> tls.with_keyfile(keyfile: "./certs/client-key.pem")
```

## Development-only insecure mode

`tls.with_verify(verify: tls.VerifyNone)` is useful for local testing against self-signed endpoints, but it skips peer certificate verification. Do not ship it in production.

See the [connection reference](/reference/gluegun-connection/) and [tls reference](/reference/gluegun-tls/) for the full API.
