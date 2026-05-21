//// Error types returned by Gluegun effectful APIs.
////
//// Match variants such as `Timeout`, `ConnectionDown`, and `InvalidMessage`
//// for application-specific recovery, and keep a fallback for Erlang or decode
//// errors.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode as dyn_decode
import gleam/erlang/atom
import gleam/string

/// Errors returned by Gluegun connection, request, message, and WebSocket APIs.
///
/// Match the variants relevant to your application and keep a fallback for
/// `ErlangError` / `DecodeError`, which can occur when Gun returns shapes
/// Gluegun cannot normalize.
pub type GluegunError {
  /// An operation did not complete within the configured `Timeout`. Retry,
  /// extend the timeout, or fall back to a degraded path.
  Timeout
  /// Gun reported the connection went down. The string carries Gun's reason.
  /// Reopen the connection before retrying.
  ConnectionDown(String)
  /// Gun could not establish or maintain the connection (DNS, TCP, TLS).
  /// Inspect the reason string and adjust transport or TLS options.
  ConnectionError(String)
  /// A stream-level error occurred (cancelled, reset, protocol error).
  /// Open a new stream; the connection may still be usable.
  StreamError(String)
  /// Caller passed options Gun rejected (e.g. non-positive flow window).
  /// Fix the options and retry.
  InvalidOptions(String)
  /// Gun delivered a message Gluegun could not classify, or the high-level
  /// `client` helpers received push/upgrade/WebSocket on a regular request.
  /// Use the low-level `request`/`message` APIs for those flows.
  InvalidMessage(String)
  /// The requested feature is not supported (e.g. WebSocket over HTTP/2).
  /// Choose an alternative protocol or transport.
  UnsupportedFeature(String)
  /// A generic Erlang-side error that did not match a tagged shape. Inspect
  /// the reason string for debugging.
  ErlangError(String)
  /// A response body, frame, or message could not be decoded into the
  /// expected Gleam type. Often a UTF-8 or protocol-shape mismatch.
  DecodeError(String)
}

/// Decode an FFI error reason into a Gluegun error.
@internal
pub fn decode_ffi_error(error: Dynamic) -> GluegunError {
  case dyn_decode.run(error, atom.decoder()) {
    Ok(tag) ->
      case atom.to_string(tag) {
        "timeout" -> Timeout
        _ -> ErlangError(string.inspect(error))
      }
    Error(_) -> decode_tagged_ffi_error(error)
  }
}

fn decode_tagged_ffi_error(error: Dynamic) -> GluegunError {
  let tag_result = dyn_decode.run(error, dyn_decode.at([0], atom.decoder()))
  let reason_result =
    dyn_decode.run(error, dyn_decode.at([1], dyn_decode.dynamic))

  case tag_result, reason_result {
    Ok(tag), Ok(reason) -> {
      let reason = string.inspect(reason)
      case atom.to_string(tag) {
        "invalid_options" -> InvalidOptions(reason)
        "connection_down" -> ConnectionDown(reason)
        "connection_error" -> ConnectionError(reason)
        "stream_error" -> StreamError(reason)
        "invalid_message" -> InvalidMessage(reason)
        "unsupported_feature" -> UnsupportedFeature(reason)
        "erlang_error" -> ErlangError(reason)
        _ -> ErlangError(string.inspect(error))
      }
    }
    _, _ -> ErlangError(string.inspect(error))
  }
}
