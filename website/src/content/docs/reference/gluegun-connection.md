---
title: gluegun/connection
description: Connection management for Erlang Gun.
---

Connection management for Erlang Gun.

 Open a Gun process, wait for it to be ready, choose transport and HTTP
 protocol preferences, then close or shut down the connection. Connections
 are Erlang process resources and are available on the Erlang target only.

## Types

### `ConnectOptions`

Pure representation of connection options before FFI conversion.

 Build with `options()` then chain `with_transport`, `with_protocols`,
 `with_retry`, `with_connect_timeout`, and `with_tls_opts`. Pass the
 result to `open(host:, port:)`.

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

### `Timeout`

Timeout or retry duration in milliseconds, or no limit.

```gleam
pub type Timeout {
  Milliseconds(Int)
  Infinity
}
```

#### Constructors

##### `Milliseconds(Int)`

A finite duration in milliseconds. Must be non-negative.

##### `Infinity`

No upper bound. Wait indefinitely.

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

Let Gun choose TLS for TLS ports and TCP otherwise.

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

Close a Gun connection cleanly.

 Sends Gun's shutdown signal and waits for the process to exit. Safe to
 call once per connection. Outstanding streams are cancelled.

```gleam
pub fn close(internal.Connection) -> Result(Nil, error.GluegunError)
```

### `connect_timeout`

Inspect connect timeout duration.

```gleam
pub fn connect_timeout(ConnectOptions) -> Timeout
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

### `protocols`

Inspect explicitly configured protocol ordering, if any.

```gleam
pub fn protocols(ConnectOptions) -> option.Option(List(Protocol))
```

### `retry`

Inspect retry duration.

```gleam
pub fn retry(ConnectOptions) -> Timeout
```

### `shutdown`

Shut down a Gun connection immediately.

 Terminates the Gun process without waiting for graceful close. Prefer
 `close` for normal teardown; use `shutdown` when the connection is
 suspected stuck.

```gleam
pub fn shutdown(internal.Connection) -> Result(Nil, error.GluegunError)
```

### `tls_opts`

Inspect explicitly configured TLS options, if any.

```gleam
pub fn tls_opts(ConnectOptions) -> option.Option(tls.TlsOptions)
```

### `transport`

Inspect configured transport. Intended for tests and later FFI conversion.

```gleam
pub fn transport(ConnectOptions) -> Transport
```

### `with_connect_timeout`

Set Gun's connect timeout option.

```gleam
pub fn with_connect_timeout(
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

Set Gun's retry timeout option.

```gleam
pub fn with_retry(
  ConnectOptions,
  retry: Timeout
) -> ConnectOptions
```

### `with_tls_opts`

Set TLS options for TLS or auto-transport connections.

```gleam
pub fn with_tls_opts(
  ConnectOptions,
  tls_opts: tls.TlsOptions
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
