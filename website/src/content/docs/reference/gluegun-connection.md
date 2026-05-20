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

## Functions

### `await_up`

Wait until a Gun connection is up.

```gleam
pub fn await_up(gluegun/internal.Connection, gluegun/connection.Timeout) -> Result(gluegun/connection.Protocol, gluegun/error.GluegunError)
```

### `close`

Close a Gun connection.

```gleam
pub fn close(gluegun/internal.Connection) -> Result(Nil, gluegun/error.GluegunError)
```

### `connect_timeout`

Inspect connect timeout duration.

```gleam
pub fn connect_timeout(gluegun/connection.ConnectOptions) -> gluegun/connection.Timeout
```

### `open`

Open a Gun connection.

```gleam
pub fn open(gluegun/connection.ConnectOptions, host: String, port: Int) -> Result(gluegun/internal.Connection, gluegun/error.GluegunError)
```

### `options`

Construct default connection options.

```gleam
pub fn options() -> gluegun/connection.ConnectOptions
```

### `options_to_ffi`

Convert connection options to the Erlang FFI map shape.

```gleam
pub fn options_to_ffi(gluegun/connection.ConnectOptions) -> gleam/dynamic.Dynamic
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

Shut down a Gun connection.

```gleam
pub fn shutdown(gluegun/internal.Connection) -> Result(Nil, gluegun/error.GluegunError)
```

### `timeout_to_ffi`

Convert a timeout to the Erlang FFI shape.

```gleam
pub fn timeout_to_ffi(gluegun/connection.Timeout) -> gleam/dynamic.Dynamic
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
