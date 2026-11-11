---
title: gluegun/connection
description: Connection management for Erlang Gun.
---

Connection management for Erlang Gun.

 Open a Gun process, wait for it to be ready, choose transport and HTTP
 protocol preferences, then close or shut down the connection. Connections
 are Erlang process resources and are available on the Erlang target only.

## Types

### `AddressFamily`

Address family for DNS lookup and socket connection, without fallback.

```gleam
pub type AddressFamily {
  Ipv4
  Ipv6
}
```

### `ConnectOptions`

Pure representation of connection options before FFI conversion.

 Build with `options()` and the `with_*` builders. Configure retry count,
 address family, separate setup timeouts, and TLS options as needed, then
 pass the result to `open(host:, port:)`.

```gleam
pub type ConnectOptions
```

### `Protocol`

HTTP protocol preference for a Gun connection.

 This type is closed; new variants are a breaking change. Pin to a major
 version.

 `Http2` is encoded as Gun's `http2` protocol atom, so it can be placed
 before `Http1` when TLS + ALPN should prefer HTTP/2 and fall back to
 HTTP/1.1.

```gleam
pub type Protocol {
  Http1
  Http2
}
```

#### Constructors

##### `Http1`

HTTP/1.1. Required for WebSocket upgrades.

##### `Http2`

HTTP/2. Negotiated via ALPN when paired with TLS.

### `RetryCount`

Number of reconnection attempts after the initial connection attempt.

```gleam
pub type RetryCount
```

### `Timeout`

Timeout in milliseconds, or no limit.

```gleam
pub type Timeout
```

### `Transport`

Transport selection for a Gun connection.

 This type is closed; new variants are a breaking change. Pin to a major
 version.

```gleam
pub type Transport {
  Auto
  Tcp
  Tls
}
```

#### Constructors

##### `Auto`

Use TLS on port 443 and TCP on all other ports.
 TCP connections do not load TLS trust roots.

 If TLS options are configured with `with_tls_options`, Auto uses TLS
 on every port instead: configured TLS options are treated as explicit
 TLS intent, so they are never silently discarded on non-443 ports.

##### `Tcp`

Force plain TCP (no TLS). Use for `http://` endpoints.

##### `Tls`

Force TLS. Combine with `tls.with_*` builders for verification settings.

## Type aliases

### `Connection`

Opaque handle for an open Gun connection.

```gleam
pub type Connection = internal.Connection
```

## Functions

### `await_up`

Wait until a Gun connection is up and return the negotiated protocol.

 Call after `open` and before any request, WebSocket upgrade, or close.
 Blocks the caller process until Gun reports readiness or `timeout` elapses.

 Errors:
 - `Timeout` — Gun did not report ready within `timeout`.
 - `ConnectionDown` / `ConnectionError` — handshake failed.
 - `DecodeError` — Gun returned an unrecognized protocol atom.

```gleam
pub fn await_up(
  internal.Connection,
  Timeout
) -> Result(Protocol, error.GluegunError)
```

### `close`

Stop a Gun connection through its supervisor.

 Gun's supervisor waits for process exit, with a supervisor shutdown
 timeout before forced termination. This is not a graceful HTTP drain.
 It does not flush the caller's mailbox. Use `terminate` for a stalled
 connection or deadline cleanup.

```gleam
pub fn close(internal.Connection) -> Result(Nil, error.GluegunError)
```

### `infinity`

Construct a timeout with no upper bound.

```gleam
pub fn infinity() -> Timeout
```

### `milliseconds`

Construct a finite timeout.

 Returns `InvalidOptions` if `value` is negative.

```gleam
pub fn milliseconds(Int) -> Result(Timeout, error.GluegunError)
```

### `open`

Open a Gun connection to `host:port`.

 Returns immediately with a `Connection` handle; the underlying TCP/TLS
 handshake completes asynchronously. Call `await_up` before sending any
 request or WebSocket upgrade.

 Errors:
 - `InvalidOptions` — Gun rejected the converted options.
 - `ErlangError` — Gun could not spawn the connection process.

```gleam
pub fn open(
  ConnectOptions,
  host: String,
  port: Int
) -> Result(internal.Connection, error.GluegunError)
```

### `options`

Construct default connection options.

```gleam
pub fn options() -> ConnectOptions
```

### `retry_count`

Construct a retry count. Zero disables retries; negative values are invalid.

```gleam
pub fn retry_count(Int) -> Result(RetryCount, error.GluegunError)
```

### `shutdown`

Request graceful shutdown of a Gun connection.

 Sends an asynchronous cast. Gun can finish active streams before it
 exits; this call does not wait for exit and cannot interrupt blocked setup.

```gleam
pub fn shutdown(internal.Connection) -> Result(Nil, error.GluegunError)
```

### `terminate`

Force termination, wait for process exit, then flush its Gun messages.

 Use on deadline expiry, including during DNS, connect, or TLS setup.
 Call from the process that receives the connection's messages. On return,
 the Gun process cannot send more messages and its queued messages are gone.
 This does not drain other receiving processes or third-party forwarders.
 It discards all streams on this connection, not only one stream.

```gleam
pub fn terminate(internal.Connection) -> Result(Nil, error.GluegunError)
```

### `with_address_family`

Select only IPv4 or only IPv6 for DNS lookup and TCP connection.

 TLS uses the same TCP setup. This does not change TLS verification or SNI.
 With no selection, Gun uses the runtime's default address family.

```gleam
pub fn with_address_family(
  ConnectOptions,
  family: AddressFamily
) -> ConnectOptions
```

### `with_connect_timeout`

Bound socket connection across the resolved addresses in one attempt.

 This does not cover DNS lookup or TLS handshake. Use
 `with_domain_lookup_timeout` and `with_tls_handshake_timeout` for those.

```gleam
pub fn with_connect_timeout(
  ConnectOptions,
  timeout: Timeout
) -> ConnectOptions
```

### `with_domain_lookup_timeout`

Bound DNS lookup per connection attempt. Gun defaults to no limit.

```gleam
pub fn with_domain_lookup_timeout(
  ConnectOptions,
  timeout: Timeout
) -> ConnectOptions
```

### `with_protocols`

Set HTTP protocol preference ordering for a connection.

 The list order is preserved when options are passed to Gun.

```gleam
pub fn with_protocols(
  ConnectOptions,
  protocols: List(Protocol)
) -> ConnectOptions
```

### `with_retry`

Set Gun's retry count, including zero to disable retries.

 Gun waits five seconds between subsequent retries by default. This count
 does not set that delay or any setup timeout.

```gleam
pub fn with_retry(
  ConnectOptions,
  retry: RetryCount
) -> ConnectOptions
```

### `with_tls_handshake_timeout`

Bound the TLS handshake per connection attempt. Gun defaults to no limit.

```gleam
pub fn with_tls_handshake_timeout(
  ConnectOptions,
  timeout: Timeout
) -> ConnectOptions
```

### `with_tls_options`

Set TLS options for TLS or auto-transport connections.

 Configuring TLS options on an `Auto`-transport connection is treated as
 explicit TLS intent: the connection uses TLS on every port, not only
 port 443, so the configured options are never silently dropped in favor
 of plaintext.

```gleam
pub fn with_tls_options(
  ConnectOptions,
  tls_options: tls.TlsOptions
) -> ConnectOptions
```

### `with_transport`

Set the transport Gun should use for a connection.

```gleam
pub fn with_transport(
  ConnectOptions,
  transport: Transport
) -> ConnectOptions
```
