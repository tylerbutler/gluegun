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
  /// Use TLS on port 443 and TCP on all other ports.
  /// TCP connections do not load TLS trust roots.
  ///
  /// If TLS options are configured with `with_tls_options`, Auto uses TLS
  /// on every port instead: configured TLS options are treated as explicit
  /// TLS intent, so they are never silently discarded on non-443 ports.
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

/// Timeout in milliseconds, or no limit.
pub opaque type Timeout {
  /// A finite duration in milliseconds. Must be non-negative.
  Milliseconds(Int)
  /// No upper bound. Wait indefinitely.
  Infinity
}

/// Address family for DNS lookup and socket connection, without fallback.
pub type AddressFamily {
  Ipv4
  Ipv6
}

/// Number of reconnection attempts after the initial connection attempt.
pub opaque type RetryCount {
  RetryCount(Int)
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
  RetryOption(RetryCount)
  ConnectTimeoutOption(Timeout)
  AddressFamilyOption(AddressFamily)
  DomainLookupTimeoutOption(Timeout)
  TlsHandshakeTimeoutOption(Timeout)
  TlsOption(List(tls.TlsSetting))
}

/// Pure representation of connection options before FFI conversion.
///
/// Build with `options()` and the `with_*` builders. Configure retry count,
/// address family, separate setup timeouts, and TLS options as needed, then
/// pass the result to `open(host:, port:)`.
pub opaque type ConnectOptions {
  ConnectOptions(
    transport: Transport,
    protocols: Option(List(Protocol)),
    retry: RetryCount,
    connect_timeout: Timeout,
    tls_options: Option(tls.TlsOptions),
    address_family: Option(AddressFamily),
    domain_lookup_timeout: Option(Timeout),
    tls_handshake_timeout: Option(Timeout),
  )
}

/// Construct default connection options.
pub fn options() -> ConnectOptions {
  ConnectOptions(
    transport: Auto,
    protocols: None,
    retry: default_retry_count(),
    connect_timeout: default_timeout(),
    tls_options: None,
    address_family: None,
    domain_lookup_timeout: None,
    tls_handshake_timeout: None,
  )
}

/// Construct a retry count. Zero disables retries; negative values are invalid.
pub fn retry_count(value: Int) -> Result(RetryCount, error.GluegunError) {
  case value >= 0 {
    True -> Ok(RetryCount(value))
    False -> Error(error.InvalidOptions("retry count must be non-negative"))
  }
}

/// Gun's default of five retries after the first attempt.
@internal
pub fn default_retry_count() -> RetryCount {
  RetryCount(5)
}

/// Construct a finite timeout.
///
/// Returns `InvalidOptions` if `value` is negative.
pub fn milliseconds(value: Int) -> Result(Timeout, error.GluegunError) {
  case value >= 0 {
    True -> Ok(Milliseconds(value))
    False -> Error(error.InvalidOptions("timeout must be non-negative"))
  }
}

/// Construct a timeout with no upper bound.
pub fn infinity() -> Timeout {
  Infinity
}

/// Construct the default five-second timeout.
@internal
pub fn default_timeout() -> Timeout {
  Milliseconds(5000)
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

/// Set Gun's retry count, including zero to disable retries.
///
/// Gun waits five seconds between subsequent retries by default. This count
/// does not set that delay or any setup timeout.
pub fn with_retry(
  options: ConnectOptions,
  retry retry: RetryCount,
) -> ConnectOptions {
  ConnectOptions(..options, retry: retry)
}

/// Bound socket connection across the resolved addresses in one attempt.
///
/// This does not cover DNS lookup or TLS handshake. Use
/// `with_domain_lookup_timeout` and `with_tls_handshake_timeout` for those.
pub fn with_connect_timeout(
  options: ConnectOptions,
  timeout timeout: Timeout,
) -> ConnectOptions {
  ConnectOptions(..options, connect_timeout: timeout)
}

/// Select only IPv4 or only IPv6 for DNS lookup and TCP connection.
///
/// TLS uses the same TCP setup. This does not change TLS verification or SNI.
/// With no selection, Gun uses the runtime's default address family.
pub fn with_address_family(
  options: ConnectOptions,
  family family: AddressFamily,
) -> ConnectOptions {
  ConnectOptions(..options, address_family: Some(family))
}

/// Bound DNS lookup per connection attempt. Gun defaults to no limit.
pub fn with_domain_lookup_timeout(
  options: ConnectOptions,
  timeout timeout: Timeout,
) -> ConnectOptions {
  ConnectOptions(..options, domain_lookup_timeout: Some(timeout))
}

/// Bound the TLS handshake per connection attempt. Gun defaults to no limit.
pub fn with_tls_handshake_timeout(
  options: ConnectOptions,
  timeout timeout: Timeout,
) -> ConnectOptions {
  ConnectOptions(..options, tls_handshake_timeout: Some(timeout))
}

/// Set TLS options for TLS or auto-transport connections.
///
/// Configuring TLS options on an `Auto`-transport connection is treated as
/// explicit TLS intent: the connection uses TLS on every port, not only
/// port 443, so the configured options are never silently dropped in favor
/// of plaintext.
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

/// Inspect retry count.
pub fn retry(options: ConnectOptions) -> RetryCount {
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

/// Stop a Gun connection through its supervisor.
///
/// Gun's supervisor waits for process exit, with a supervisor shutdown
/// timeout before forced termination. This is not a graceful HTTP drain.
/// It does not flush the caller's mailbox. Use `terminate` for a stalled
/// connection or deadline cleanup.
pub fn close(connection: Connection) -> Result(Nil, error.GluegunError) {
  ffi_close(connection)
}

/// Request graceful shutdown of a Gun connection.
///
/// Sends an asynchronous cast. Gun can finish active streams before it
/// exits; this call does not wait for exit and cannot interrupt blocked setup.
pub fn shutdown(connection: Connection) -> Result(Nil, error.GluegunError) {
  ffi_shutdown(connection)
}

/// Force termination, wait for process exit, then flush its Gun messages.
///
/// Use on deadline expiry, including during DNS, connect, or TLS setup.
/// Call from the process that receives the connection's messages. On return,
/// the Gun process cannot send more messages and its queued messages are gone.
/// This does not drain other receiving processes or third-party forwarders.
/// It discards all streams on this connection, not only one stream.
pub fn terminate(connection: Connection) -> Result(Nil, error.GluegunError) {
  ffi_terminate(connection)
}

/// Convert connection options to the typed shape the Erlang FFI expects.
@internal
pub fn options_to_ffi(options: ConnectOptions) -> List(ConnectOption) {
  let protocol_options = case options.protocols {
    Some(protocols) -> [ProtocolsOption(protocols)]
    None -> []
  }

  let tls_options = case options.transport, options.tls_options {
    Auto, Some(tls_options) | Tls, Some(tls_options) -> [
      TlsOption(tls.to_ffi(tls_options)),
    ]
    Auto, None | Tcp, None | Tcp, Some(_) | Tls, None -> []
  }

  let family_options = case options.address_family {
    Some(family) -> [AddressFamilyOption(family)]
    None -> []
  }
  let lookup_options = case options.domain_lookup_timeout {
    Some(timeout) -> [DomainLookupTimeoutOption(timeout)]
    None -> []
  }
  let handshake_options = case options.tls_handshake_timeout {
    Some(timeout) -> [TlsHandshakeTimeoutOption(timeout)]
    None -> []
  }

  list.flatten([
    [
      TransportOption(options.transport),
      RetryOption(options.retry),
      ConnectTimeoutOption(options.connect_timeout),
    ],
    protocol_options,
    tls_options,
    family_options,
    lookup_options,
    handshake_options,
  ])
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

@external(erlang, "gluegun_ffi", "terminate")
fn ffi_terminate(connection: Connection) -> Result(Nil, error.GluegunError)
