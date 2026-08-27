---
title: TLS
description: Secure TLS defaults, and how to change or disable them.
---

Gluegun gives access to Erlang SSL client options through `gluegun/tls`.

## Secure by default

When a connection uses TLS (`connection.Tls`, or `connection.Auto` that
resolves to TLS), Gluegun applies a secure baseline when it opens the
connection:

| Default | Value |
|---|---|
| `verify` | `verify_peer` (chain and hostname verification) |
| `cacerts` | OS trust store through `public_key:cacerts_get/0` |
| `versions` | `[tlsv1.3, tlsv1.2]` |
| `depth` | `10` |
| `server_name_indication` | The host given to `connection.open` (not set for IP literals) |
| `customize_hostname_check` | HTTPS match function from `public_key:pkix_verify_hostname_match_fun(https)` |

Thus the minimum HTTPS setup is:

```gleam
import gluegun/connection

pub fn open_secure() {
  connection.options()
  |> connection.with_transport(transport: connection.Tls)
  |> connection.open(host: "example.com", port: 443)
}
```

Fields that you set on `tls.TlsOptions` always replace the defaults. The
baseline fills each field that you do not set.

`public_key:cacerts_get/0` is available on OTP 25 and newer. Gluegun
currently pins OTP 27 in CI. If no system trust store is available (for
example, in a minimal container), `connection.open` returns an
`InvalidOptions` TLS error. The reason includes `no_system_cacerts`. In that
case, supply your own CA bundle with `tls.with_cacertfile` or
`tls.with_cacerts`.

## Auto transport keeps configured TLS options

`connection.Auto` (the default transport) usually lets Gun select TLS on
port 443 and plain TCP on all other ports. If you set TLS options with
`with_tls_options` when `Auto` is active, Gluegun reads this as explicit TLS
intent. The connection then uses TLS on each port, not only on 443. This
prevents a fallback to plaintext on an incorrect or non-standard TLS port
(for example, a proxy that terminates TLS on port 8443). Your TLS settings
are not discarded.

```gleam
import gluegun/connection
import gluegun/tls

pub fn open_secure_on_custom_port() {
  connection.options()
  |> connection.with_tls_options(tls.options())
  |> connection.open(host: "example.com", port: 8443)
  // Uses TLS even though the port is not 443, because TLS options were
  // explicitly configured.
}
```

`Auto` connections without TLS options do not change: Gun selects the
transport only from the port number.

## Change the baseline

```gleam
import gluegun/connection
import gluegun/tls

pub fn secure_options() {
  let tls_options =
    tls.options()
    |> tls.with_versions(versions: [tls.TlsV13])
    |> tls.with_cacertfile(cacertfile: "/etc/ssl/cert.pem")
    |> tls.with_depth(depth: 5)

  connection.options()
  |> connection.with_transport(transport: connection.Tls)
  |> connection.with_tls_opts(tls_opts: tls_options)
}
```

`with_versions` replaces the default `tlsv1.3 + tlsv1.2`. `with_cacertfile`
(or `with_cacerts`) replaces the system trust store. `with_depth` replaces
`10`. The other fields keep the secure defaults (peer verification, SNI from
the host, hostname match function).

## Full typed option list

`gluegun/tls` has these typed builders:

| Builder | Effect |
|---|---|
| `with_verify(VerifyPeer\|VerifyNone)` | Peer chain and hostname verification |
| `with_versions([TlsV12, TlsV13])` | Set the permitted TLS versions |
| `with_ciphers([...])` | Set the permitted cipher suite names |
| `with_cacerts([DER...])` | DER-encoded trusted CAs |
| `with_cacertfile("/path/ca.pem")` | Path to a PEM CA bundle |
| `with_certfile("/path/client.pem")` | Client certificate (mTLS) |
| `with_keyfile("/path/client.key")` | Client private key (mTLS) |
| `with_server_name_indication(ServerName\|Disable)` | SNI value |
| `with_depth(N)` | Maximum certificate chain depth |

## Client certificate authentication

Use `certfile` and `keyfile` when the server requires mTLS. Verification
and SNI keep their defaults:

```gleam
let tls_options =
  tls.options()
  |> tls.with_certfile(certfile: "./certs/client.pem")
  |> tls.with_keyfile(keyfile: "./certs/client-key.pem")
```

## Insecure mode for development only

For tests against self-signed endpoints, use `tls.insecure()`:

```gleam
connection.options()
|> connection.with_transport(transport: connection.Tls)
|> connection.with_tls_opts(tls_opts: tls.insecure())
|> connection.open(host: "localhost", port: 8443)
```

`tls.insecure()` sets `verify_none` and disables SNI. This also disables
the rest of the secure baseline (no system trust store lookup, no hostname
match function). **Do not** use this on untrusted networks or production
endpoints. It removes each protection that makes HTTPS safe.

See the [connection reference](/reference/gluegun-connection/) and
[tls reference](/reference/gluegun-tls/) for the full API.
