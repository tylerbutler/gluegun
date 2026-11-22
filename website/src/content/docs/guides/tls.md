---
title: TLS
description: Secure TLS defaults, and how to change or disable them.
---

Each TLS connection in Gluegun starts from a secure baseline. You can
connect to most HTTPS servers without any TLS options. When a server needs
something different, `gluegun/tls` gives typed access to the Erlang SSL client
options, and each option that you set replaces one part of the baseline.

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
| `server_name_indication` | The DNS host without its final root dot (not set for IP literals) |
| `customize_hostname_check` | HTTPS match function from `public_key:pkix_verify_hostname_match_fun(https)` |

Because the baseline covers verification, trust, and identity, the minimum
HTTPS setup only selects the transport:

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

### Server identity

The baseline verifies the host that you give to `connection.open`, so the
form of that host matters. `connection.open` accepts IPv4 text and IPv6 text
with or without brackets,
such as `127.0.0.1`, `::1`, and `[::1]`. Gluegun passes these as address tuples
to Gun. IPv6 HTTP authorities then use brackets, such as `[::1]:8443`.
IP connections keep certificate chain and IP identity verification; they do
not disable SNI to bypass verification. The certificate must identify the
target IP unless you set an explicit DNS identity with `ServerName`.

DNS names work in a similar way. An absolute DNS name such as `service.example.` keeps its final root dot for
DNS lookup. Only the derived SNI removes that dot: `service.example`.
An explicit `ServerName` is passed through unchanged and selects the TLS
certificate identity as well as SNI.

### System trust store

The baseline also needs a trust store. `public_key:cacerts_get/0` is
available on OTP 25 and newer, and Gluegun pins OTP 27 in CI. If no system
trust store is available (for
example, in a minimal container), `connection.open` returns an
`InvalidOptions` TLS error. The reason includes `no_system_cacerts`. In that
case, supply your own CA bundle with `tls.with_cacertfile` or
`tls.with_cacerts`.

## Auto transport keeps configured TLS options

The baseline applies only when the connection uses TLS. With the default
transport, `connection.Auto`, the port usually decides. `connection.Auto` uses TLS on port 443 and plain
TCP on all other ports when you do not configure TLS options. Gluegun
resolves this transport before it applies TLS defaults. Plain TCP does
not load CA certificates or apply other TLS defaults.

If you set TLS options with
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

TLS setup failures return errors. Gluegun does not retry a failed TLS
connection as plaintext. Explicit `connection.Tcp` and `connection.Tls`
use the selected transport on each port.

## Change the baseline

```gleam
import gluegun/connection
import gluegun/tls

pub fn secure_options() {
  let assert Ok(tls_options) =
    tls.options()
    |> tls.with_versions(versions: [tls.TlsV13])
    |> tls.with_cacertfile(cacertfile: "/etc/ssl/cert.pem")
    |> tls.with_depth(depth: 5)

  connection.options()
  |> connection.with_transport(transport: connection.Tls)
  |> connection.with_tls_options(tls_options: tls_options)
}
```

`with_versions` replaces the default `tlsv1.3 + tlsv1.2`. `with_cacertfile`
(or `with_cacerts`) replaces the system trust store. `with_depth` replaces
`10`. The other fields keep the secure defaults (peer verification, SNI from
the host, hostname match function).

Of these builders, only `with_depth` can fail. It returns `Result` and accepts 0 through 255. Numeric builders
reject out-of-range values; they do not clamp them. Handle the error when the
depth comes from configuration.

Some changes cannot keep the baseline's promise, so Gluegun rejects them.
Disabled SNI with `VerifyPeer`, including the default verifying mode, is one
of them. OTP disables hostname verification along with SNI, so this combination
cannot meet the verifying contract. Leave SNI unset for the target identity,
or use a valid `ServerName` to select a DNS identity for verified TLS.
`tls.insecure()` remains a development-only verification bypass.

Cipher lists have a similar check. `with_ciphers` sets an explicit list of permitted cipher suite names. At least
one suite must be usable with the effective TLS versions. Gluegun returns
`InvalidOptions` before it starts Gun if the list is empty or has no usable
suite. You can combine suites for different versions in one list if at least
one suite is usable. This check also applies to `tls.insecure()`, which uses
the runtime's default versions unless you set `with_versions`. Leave ciphers
unset to keep OTP defaults.

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

Sometimes you must turn the baseline off, for example in a test against a
self-signed endpoint. Use `tls.insecure()` only for that purpose:

```gleam
connection.options()
|> connection.with_transport(transport: connection.Tls)
|> connection.with_tls_options(tls_options: tls.insecure())
|> connection.open(host: "localhost", port: 8443)
```

`tls.insecure()` sets `verify_none` and disables SNI. This also disables
the rest of the secure baseline (no system trust store lookup, no hostname
match function). **Do not** use this on untrusted networks or production
endpoints. It removes each protection that makes HTTPS safe.

With explicit `VerifyNone`, Gluegun supplies an empty CA list if neither
`with_cacerts` nor `with_cacertfile` is set. This prevents Gun from reading
the system trust store during TLS setup. Explicit CA settings are kept.
Verifying connections keep the secure defaults.

See the [connection reference](/reference/gluegun-connection/) and
[tls reference](/reference/gluegun-tls/) for the full API.
