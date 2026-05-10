import gleam/option.{type Option, None, Some}

/// Transport selection for a Gun connection.
pub type Transport {
  /// Let Gun choose TLS for TLS ports and TCP otherwise.
  Auto
  Tcp
  Tls
}

/// HTTP protocol preference for a Gun connection.
pub type Protocol {
  Http1
  Http2
}

/// Timeout or retry duration in milliseconds, or no limit.
pub type Timeout {
  Milliseconds(Int)
  Infinity
}

/// Pure representation of connection options before FFI conversion.
pub opaque type ConnectOptions {
  ConnectOptions(
    transport: Transport,
    protocols: Option(List(Protocol)),
    retry: Timeout,
    connect_timeout: Timeout,
  )
}

/// Construct default connection options.
pub fn connect_options() -> ConnectOptions {
  ConnectOptions(
    transport: Auto,
    protocols: None,
    retry: Milliseconds(5000),
    connect_timeout: Milliseconds(5000),
  )
}

pub fn with_transport(
  options: ConnectOptions,
  transport transport: Transport,
) -> ConnectOptions {
  ConnectOptions(..options, transport: transport)
}

pub fn with_protocols(
  options: ConnectOptions,
  protocols protocols: List(Protocol),
) -> ConnectOptions {
  ConnectOptions(..options, protocols: Some(protocols))
}

pub fn with_retry(
  options: ConnectOptions,
  retry retry: Timeout,
) -> ConnectOptions {
  ConnectOptions(..options, retry: retry)
}

pub fn with_connect_timeout(
  options: ConnectOptions,
  timeout timeout: Timeout,
) -> ConnectOptions {
  ConnectOptions(..options, connect_timeout: timeout)
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
