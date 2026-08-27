---
title: TLS
description: Secure-by-default TLS, and how to override or opt out.
---

Gluegun exposes Erlang SSL client options through `gluegun/tls`.

## Secure by default

Whenever a connection uses TLS (`connection.Tls`, or `connection.Auto`
resolving to TLS), Gluegun applies a secure baseline at connection time:

| Default | Value |
|---|---|
| `verify` | `verify_peer` (chain + hostname verification) |
| `cacerts` | OS trust store via `public_key:cacerts_get/0` |
| `versions` | `[tlsv1.3, tlsv1.2]` |
| `depth` | `10` |
| `server_name_indication` | host passed to `connection.open` (skipped for IP literals) |
| `customize_hostname_check` | HTTPS match function from `public_key:pkix_verify_hostname_match_fun(https)` |

The minimal HTTPS setup is therefore just:

```gleam
import gluegun/connection

pub fn open_secure() {
  connection.options()
  |> connection.with_transport(transport: connection.Tls)
  |> connection.open(host: "example.com", port: 443)
}
```

User-supplied fields on `tls.TlsOptions` always win over the defaults. Any
field you leave unset is filled in by the baseline.

`public_key:cacerts_get/0` is available on OTP 25 and newer. Gluegun
currently pins OTP 27 in CI. If no system trust store is available (for
example, in a minimal container), `connection.open` returns an
`InvalidOptions` TLS error whose reason includes `no_system_cacerts`.
Supply your own CA bundle with `tls.with_cacertfile` or `tls.with_cacerts`
in that case.

## Auto transport never silently drops configured TLS options

`connection.Auto` (the default transport) normally lets Gun choose TLS on
port 443 and plain TCP everywhere else. If you configure TLS options with
`with_tls_options` while `Auto` is active, that is treated as explicit TLS
intent: the connection uses TLS on every port, not only 443. This keeps a
misconfigured or non-standard TLS port (for example a proxy that terminates
TLS on port 8443) from silently falling back to plaintext and discarding
your TLS settings.

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

Auto connections that never configure TLS options are unaffected: Gun still
chooses transport purely from the port number.

## Overriding the baseline

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

Setting `with_versions` overrides the `tlsv1.3 + tlsv1.2` default;
`with_cacertfile` (or `with_cacerts`) replaces the system trust store;
`with_depth` overrides `10`. Leaving the rest unset keeps the secure
defaults (peer verification, SNI from host, hostname match function).

## Full typed option surface

`gluegun/tls` exposes the following typed builders:

| Builder | Effect |
|---|---|
| `with_verify(VerifyPeer\|VerifyNone)` | Peer chain + hostname verification |
| `with_versions([TlsV12, TlsV13])` | Pin allowed TLS versions |
| `with_ciphers([...])` | Set allowed cipher suite names |
| `with_cacerts([DER...])` | DER-encoded trusted CAs |
| `with_cacertfile("/path/ca.pem")` | PEM CA bundle path |
| `with_certfile("/path/client.pem")` | Client cert (mTLS) |
| `with_keyfile("/path/client.key")` | Client private key (mTLS) |
| `with_server_name_indication(ServerName\|Disable)` | SNI value |
| `with_depth(N)` | Maximum certificate chain depth |

## Client certificate authentication

Use `certfile` and `keyfile` when the server requires mTLS. Verification
and SNI are still defaulted:

```gleam
let tls_options =
  tls.options()
  |> tls.with_certfile(certfile: "./certs/client.pem")
  |> tls.with_keyfile(keyfile: "./certs/client-key.pem")
```

## Development-only insecure mode

For testing against self-signed endpoints, use `tls.insecure()`:

```gleam
connection.options()
|> connection.with_transport(transport: connection.Tls)
|> connection.with_tls_opts(tls_opts: tls.insecure())
|> connection.open(host: "localhost", port: 8443)
```

`tls.insecure()` sets `verify_none` and disables SNI, which suppresses the
rest of the secure baseline (no system trust store lookup, no hostname
match function). **Never** ship this against untrusted networks or
production endpoints — it bypasses every protection that makes HTTPS
trustworthy.

See the [connection reference](/reference/gluegun-connection/) and
[tls reference](/reference/gluegun-tls/) for the full API.
