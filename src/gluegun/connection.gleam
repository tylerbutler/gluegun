//// Connection management for Erlang Gun.
////
//// Open a Gun process, wait for it to be ready, choose transport and HTTP
//// protocol preferences, then close or shut down the connection. Connections
//// are Erlang process resources and are available on the Erlang target only.

import gleam/dynamic
import gleam/erlang/atom
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gluegun/error
import gluegun/internal.{type Connection}

/// Transport selection for a Gun connection.
pub type Transport {
  /// Let Gun choose TLS for TLS ports and TCP otherwise.
  Auto
  Tcp
  Tls
}

/// HTTP protocol preference for a Gun connection.
///
/// `Http2` is encoded as Gun's `http2` protocol atom, so it can be placed
/// before `Http1` when TLS + ALPN should prefer HTTP/2 and fall back to
/// HTTP/1.1.
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
pub fn options() -> ConnectOptions {
  ConnectOptions(
    transport: Auto,
    protocols: None,
    retry: Milliseconds(5000),
    connect_timeout: Milliseconds(5000),
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

/// Open a Gun connection.
pub fn open(
  options: ConnectOptions,
  host host: String,
  port port: Int,
) -> Result(Connection, error.GluegunError) {
  ffi_open(host, port, options_to_ffi(options))
  |> result.map(internal.connection)
  |> result.map_error(error.decode_ffi_error)
}

/// Wait until a Gun connection is up.
pub fn await_up(
  connection: Connection,
  timeout: Timeout,
) -> Result(Protocol, error.GluegunError) {
  ffi_await_up(internal.connection_raw(connection), timeout_to_ffi(timeout))
  |> decode_await_up_result
}

@internal
pub fn decode_await_up_result(
  await_result: Result(dynamic.Dynamic, dynamic.Dynamic),
) -> Result(Protocol, error.GluegunError) {
  await_result
  |> result.map_error(error.decode_ffi_error)
  |> result.try(fn(protocol) {
    case decode_protocol(protocol) {
      Ok(protocol) -> Ok(protocol)
      Error(message) -> Error(error.DecodeError(message))
    }
  })
}

/// Close a Gun connection.
pub fn close(connection: Connection) -> Result(Nil, error.GluegunError) {
  ffi_close(internal.connection_raw(connection))
  |> result.map(fn(_) { Nil })
  |> result.map_error(error.decode_ffi_error)
}

/// Shut down a Gun connection.
pub fn shutdown(connection: Connection) -> Result(Nil, error.GluegunError) {
  ffi_shutdown(internal.connection_raw(connection))
  |> result.map(fn(_) { Nil })
  |> result.map_error(error.decode_ffi_error)
}

/// Convert connection options to the Erlang FFI map shape.
pub fn options_to_ffi(options: ConnectOptions) -> dynamic.Dynamic {
  let protocol_entries = case options.protocols {
    Some(protocols) -> [
      #(
        dynamic.string("protocols"),
        dynamic.list(list.map(protocols, protocol_to_ffi)),
      ),
    ]
    None -> []
  }

  dynamic.properties([
    #(dynamic.string("transport"), transport_to_ffi(options.transport)),
    #(dynamic.string("retry"), timeout_to_ffi(options.retry)),
    #(
      dynamic.string("connect_timeout"),
      timeout_to_ffi(options.connect_timeout),
    ),
    ..protocol_entries
  ])
}

/// Convert a timeout to the Erlang FFI shape.
pub fn timeout_to_ffi(timeout: Timeout) -> dynamic.Dynamic {
  case timeout {
    Milliseconds(milliseconds) -> dynamic.int(milliseconds)
    Infinity -> atom.to_dynamic(atom.create("infinity"))
  }
}

fn transport_to_ffi(transport: Transport) -> dynamic.Dynamic {
  case transport {
    Auto -> atom.to_dynamic(atom.create("auto"))
    Tcp -> atom.to_dynamic(atom.create("tcp"))
    Tls -> atom.to_dynamic(atom.create("tls"))
  }
}

fn protocol_to_ffi(protocol: Protocol) -> dynamic.Dynamic {
  case protocol {
    Http1 -> atom.to_dynamic(atom.create("http"))
    Http2 -> atom.to_dynamic(atom.create("http2"))
  }
}

fn decode_protocol(protocol: dynamic.Dynamic) -> Result(Protocol, String) {
  case dynamic.classify(protocol) {
    "Atom" -> {
      let name = atom.to_string(atom.cast_from_dynamic(protocol))
      case name {
        "http" -> Ok(Http1)
        "http2" -> Ok(Http2)
        _ -> Error("Invalid protocol")
      }
    }
    _ -> Error("Invalid protocol")
  }
}

@external(erlang, "gluegun_ffi", "open")
fn ffi_open(
  host: String,
  port: Int,
  options: dynamic.Dynamic,
) -> Result(dynamic.Dynamic, dynamic.Dynamic)

@external(erlang, "gluegun_ffi", "await_up")
fn ffi_await_up(
  connection: dynamic.Dynamic,
  timeout: dynamic.Dynamic,
) -> Result(dynamic.Dynamic, dynamic.Dynamic)

@external(erlang, "gluegun_ffi", "close")
fn ffi_close(
  connection: dynamic.Dynamic,
) -> Result(dynamic.Dynamic, dynamic.Dynamic)

@external(erlang, "gluegun_ffi", "shutdown")
fn ffi_shutdown(
  connection: dynamic.Dynamic,
) -> Result(dynamic.Dynamic, dynamic.Dynamic)
