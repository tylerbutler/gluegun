import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode as dyn_decode
import gleam/erlang/atom
import gleam/string

pub type GluegunError {
  Timeout
  ConnectionDown(String)
  ConnectionError(String)
  StreamError(String)
  InvalidOptions(String)
  InvalidMessage(String)
  ErlangError(String)
  DecodeError(String)
}

/// Decode an FFI error reason into a gluegun error.
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
        "erlang_error" -> ErlangError(reason)
        _ -> ErlangError(string.inspect(error))
      }
    }
    _, _ -> ErlangError(string.inspect(error))
  }
}
