import gleam/dynamic
import gleam/result
import gluegun/error
import gluegun/internal.{type Stream}

pub fn decode_request_result(
  result: Result(dynamic.Dynamic, dynamic.Dynamic),
) -> Result(Stream, error.GluegunError) {
  result
  |> result.map(internal.stream)
  |> result.map_error(error.decode_ffi_error)
}

pub fn decode_nil_result(
  result: Result(dynamic.Dynamic, dynamic.Dynamic),
) -> Result(Nil, error.GluegunError) {
  result
  |> result.map(fn(_) { Nil })
  |> result.map_error(error.decode_ffi_error)
}
