//// Connection management for Erlang Gun.
////
//// Open a Gun process, wait for it to be ready, choose transport and HTTP
//// protocol preferences, then close or shut down the connection. Connections
//// are Erlang process resources and are available on the Erlang target only.

import gleam/list
import gleam/option.{type Option, None, Some}
import gluegun/error
import gluegun/internal
import gluegun/tls

/// Transport selection for a Gun connection.
///
/// This type is closed; new variants are a breaking change. Pin to a major
/// version.
pub type Transport {
  /// Let Gun choose TLS for TLS ports and TCP otherwise.
  Auto
  /// Force plain TCP (no TLS). Use for `http://` endpoints.
  Tcp
  /// Force TLS. Combine with `tls.with_*` builders for verification settings.
  Tls
}

/// HTTP protocol preference for a Gun connection.
///
/// This type is closed; new variants are a breaking change. Pin to a major
/// version.
///
/// `Http2` is encoded as Gun's `http2` protocol atom, so it can be placed
/// before `Http1` when TLS + ALPN should prefer HTTP/2 and fall back to
/// HTTP/1.1.
pub type Protocol {
  /// HTTP/1.1. Required for WebSocket upgrades.
  Http1
  /// HTTP/2. Negotiated via ALPN when paired with TLS.
  Http2
}

/// Timeout or retry duration in milliseconds, or no limit.
pub type Timeout {
  /// A finite duration in milliseconds. Must be non-negative.
  Milliseconds(Int)
  /// No upper bound. Wait indefinitely.
  Infinity
}

/// Opaque handle for an open Gun connection.
pub type Connection =
  internal.Connection

/// One Gun connection option, encoded for the Erlang FFI boundary.
///
/// `options_to_ffi` turns `ConnectOptions` into a list of these values.
/// `src/gluegun_ffi.erl` pattern matches each variant and builds the matching
/// `gun:opts()` map entry, so no option ever crosses the boundary untyped.
@internal
pub type ConnectOption {
  TransportOption(Transport)
  ProtocolsOption(List(Protocol))
  RetryOption(Timeout)
  ConnectTimeoutOption(Timeout)
  TlsOption(List(tls.TlsSetting))
}

/// Pure representation of connection options before FFI conversion.
///
/// Build with `options()` then chain `with_transport`, `with_protocols`,
/// `with_retry`, `with_connect_timeout`, and `with_tls_options`. Pass the
/// result to `open(host:, port:)`.
pub opaque type ConnectOptions {
  ConnectOptions(
    transport: Transport,
    protocols: Option(List(Protocol)),
    retry: Timeout,
    connect_timeout: Timeout,
    tls_options: Option(tls.TlsOptions),
  )
}

/// Construct default connection options.
pub fn options() -> ConnectOptions {
  ConnectOptions(
    transport: Auto,
    protocols: None,
    retry: Milliseconds(5000),
    connect_timeout: Milliseconds(5000),
    tls_options: None,
  )
}

/// Set the transport Gun should use for a connection.
pub fn with_transport(
  options: ConnectOptions,
  transport transport: Transport,
) -> ConnectOptions {
  ConnectOptions(..options, transport: transport)
}

/// Set HTTP protocol preference ordering for a connection.
///
/// The list order is preserved when options are passed to Gun.
pub fn with_protocols(
  options: ConnectOptions,
  protocols protocols: List(Protocol),
) -> ConnectOptions {
  ConnectOptions(..options, protocols: Some(protocols))
}

/// Set Gun's retry timeout option.
pub fn with_retry(
  options: ConnectOptions,
  retry retry: Timeout,
) -> ConnectOptions {
  ConnectOptions(..options, retry: retry)
}

/// Set Gun's connect timeout option.
pub fn with_connect_timeout(
  options: ConnectOptions,
  timeout timeout: Timeout,
) -> ConnectOptions {
  ConnectOptions(..options, connect_timeout: timeout)
}

/// Set TLS options for TLS or auto-transport connections.
pub fn with_tls_options(
  options: ConnectOptions,
  tls_options tls_options: tls.TlsOptions,
) -> ConnectOptions {
  ConnectOptions(..options, tls_options: Some(tls_options))
}

/// Inspect configured transport. Intended for tests and later FFI conversion.
pub fn transport(options: ConnectOptions) -> Transport {
  options.transport
}

/// Inspect explicitly configured protocol ordering, if any.
pub fn protocols(options: ConnectOptions) -> Option(List(Protocol)) {
  options.protocols
}

/// Inspect retry duration.
pub fn retry(options: ConnectOptions) -> Timeout {
  options.retry
}

/// Inspect connect timeout duration.
pub fn connect_timeout(options: ConnectOptions) -> Timeout {
  options.connect_timeout
}

/// Inspect explicitly configured TLS options, if any.
pub fn tls_options(options: ConnectOptions) -> Option(tls.TlsOptions) {
  options.tls_options
}

/// Open a Gun connection to `host:port`.
///
/// Returns immediately with a `Connection` handle; the underlying TCP/TLS
/// handshake completes asynchronously. Call `await_up` before sending any
/// request or WebSocket upgrade.
///
/// Errors:
/// - `InvalidOptions` — Gun rejected the converted options.
/// - `ErlangError` — Gun could not spawn the connection process.
pub fn open(
  options: ConnectOptions,
  host host: String,
  port port: Int,
) -> Result(Connection, error.GluegunError) {
  ffi_open(host, port, options_to_ffi(options))
}

/// Wait until a Gun connection is up and return the negotiated protocol.
///
/// Call after `open` and before any request, WebSocket upgrade, or close.
/// Blocks the caller process until Gun reports readiness or `timeout` elapses.
///
/// Errors:
/// - `Timeout` — Gun did not report ready within `timeout`.
/// - `ConnectionDown` / `ConnectionError` — handshake failed.
/// - `DecodeError` — Gun returned an unrecognized protocol atom.
pub fn await_up(
  connection: Connection,
  timeout: Timeout,
) -> Result(Protocol, error.GluegunError) {
  ffi_await_up(connection, timeout)
}

/// Close a Gun connection cleanly.
///
/// Sends Gun's shutdown signal and waits for the process to exit. Safe to
/// call once per connection. Outstanding streams are cancelled.
pub fn close(connection: Connection) -> Result(Nil, error.GluegunError) {
  ffi_close(connection)
}

/// Shut down a Gun connection immediately.
///
/// Terminates the Gun process without waiting for graceful close. Prefer
/// `close` for normal teardown; use `shutdown` when the connection is
/// suspected stuck.
pub fn shutdown(connection: Connection) -> Result(Nil, error.GluegunError) {
  ffi_shutdown(connection)
}

/// Convert connection options to the typed shape the Erlang FFI expects.
@internal
pub fn options_to_ffi(options: ConnectOptions) -> List(ConnectOption) {
  let protocol_options = case options.protocols {
    Some(protocols) -> [ProtocolsOption(protocols)]
    None -> []
  }

  let tls_options = case options.transport, options.tls_options {
    Tcp, None -> []
    Tcp, Some(_) -> []
    Auto, None -> []
    Tls, None -> []
    Auto, Some(tls_options) -> [TlsOption(tls.to_ffi(tls_options))]
    Tls, Some(tls_options) -> [TlsOption(tls.to_ffi(tls_options))]
  }

  list.append(
    [
      TransportOption(options.transport),
      RetryOption(options.retry),
      ConnectTimeoutOption(options.connect_timeout),
      ..protocol_options
    ],
    tls_options,
  )
}

@external(erlang, "gluegun_ffi", "open")
fn ffi_open(
  host: String,
  port: Int,
  options: List(ConnectOption),
) -> Result(Connection, error.GluegunError)

@external(erlang, "gluegun_ffi", "await_up")
fn ffi_await_up(
  connection: Connection,
  timeout: Timeout,
) -> Result(Protocol, error.GluegunError)

@external(erlang, "gluegun_ffi", "close")
fn ffi_close(connection: Connection) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ffi", "shutdown")
fn ffi_shutdown(connection: Connection) -> Result(Nil, error.GluegunError)
