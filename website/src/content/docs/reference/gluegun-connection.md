---
title: gluegun/connection
description: Connection management for Erlang Gun.
---

# `gluegun/connection`

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



### `Protocol`

HTTP protocol preference for a Gun connection.

 This type is closed; new variants are a breaking change. Pin to a major
 version.

 `Http2` is encoded as Gun's `http2` protocol atom, so it can be placed
 before `Http1` when TLS + ALPN should prefer HTTP/2 and fall back to
 HTTP/1.1.

- `Http1()`
- `Http2()`

### `Timeout`

Timeout or retry duration in milliseconds, or no limit.

- `Milliseconds(Int)`
- `Infinity()`

### `Transport`

Transport selection for a Gun connection.

 This type is closed; new variants are a breaking change. Pin to a major
 version.

- `Auto()`
- `Tcp()`
- `Tls()`

## Type aliases

### `Connection`

Opaque handle for an open Gun connection.

```gleam
pub type Connection = gluegun/internal.Connection
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
pub fn await_up(gluegun/internal.Connection, gluegun/connection.Timeout) -> Result(gluegun/connection.Protocol, gluegun/error.GluegunError)
```

### `close`

Close a Gun connection cleanly.

 Sends Gun's shutdown signal and waits for the process to exit. Safe to
 call once per connection. Outstanding streams are cancelled.

```gleam
pub fn close(gluegun/internal.Connection) -> Result(Nil, gluegun/error.GluegunError)
```

### `connect_timeout`

Inspect connect timeout duration.

```gleam
pub fn connect_timeout(gluegun/connection.ConnectOptions) -> gluegun/connection.Timeout
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
pub fn open(gluegun/connection.ConnectOptions, host: String, port: Int) -> Result(gluegun/internal.Connection, gluegun/error.GluegunError)
```

### `options`

Construct default connection options.

```gleam
pub fn options() -> gluegun/connection.ConnectOptions
```

### `protocols`

Inspect explicitly configured protocol ordering, if any.

```gleam
pub fn protocols(gluegun/connection.ConnectOptions) -> gleam/option.Option(List(gluegun/connection.Protocol))
```

### `retry`

Inspect retry duration.

```gleam
pub fn retry(gluegun/connection.ConnectOptions) -> gluegun/connection.Timeout
```

### `shutdown`

Shut down a Gun connection immediately.

 Terminates the Gun process without waiting for graceful close. Prefer
 `close` for normal teardown; use `shutdown` when the connection is
 suspected stuck.

```gleam
pub fn shutdown(gluegun/internal.Connection) -> Result(Nil, gluegun/error.GluegunError)
```

### `tls_opts`

Inspect explicitly configured TLS options, if any.

```gleam
pub fn tls_opts(gluegun/connection.ConnectOptions) -> gleam/option.Option(gluegun/tls.TlsOptions)
```

### `transport`

Inspect configured transport. Intended for tests and later FFI conversion.

```gleam
pub fn transport(gluegun/connection.ConnectOptions) -> gluegun/connection.Transport
```

### `with_connect_timeout`

Set Gun's connect timeout option.

```gleam
pub fn with_connect_timeout(gluegun/connection.ConnectOptions, timeout: gluegun/connection.Timeout) -> gluegun/connection.ConnectOptions
```

### `with_protocols`

Set HTTP protocol preference ordering for a connection.

 The list order is preserved when options are passed to Gun.

```gleam
pub fn with_protocols(gluegun/connection.ConnectOptions, protocols: List(gluegun/connection.Protocol)) -> gluegun/connection.ConnectOptions
```

### `with_retry`

Set Gun's retry timeout option.

```gleam
pub fn with_retry(gluegun/connection.ConnectOptions, retry: gluegun/connection.Timeout) -> gluegun/connection.ConnectOptions
```

### `with_tls_opts`

Set TLS options for TLS or auto-transport connections.

```gleam
pub fn with_tls_opts(gluegun/connection.ConnectOptions, tls_opts: gluegun/tls.TlsOptions) -> gluegun/connection.ConnectOptions
```

### `with_transport`

Set the transport Gun should use for a connection.

```gleam
pub fn with_transport(gluegun/connection.ConnectOptions, transport: gluegun/connection.Transport) -> gluegun/connection.ConnectOptions
```
