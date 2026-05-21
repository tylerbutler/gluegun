//// Decoding and awaiting asynchronous Gun stream messages.
////
//// Gun sends HTTP, HTTP/2 push, upgrade, and WebSocket events as Erlang
//// messages. This module decodes those messages into Gleam types for callers
//// using lower-level streaming or advanced flows.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode as dyn_decode
import gleam/result
import gleam/string
import gluegun/connection.{type Connection, type Timeout, timeout_to_ffi}
import gluegun/error
import gluegun/fin.{type Fin, Fin, NoFin}
import gluegun/internal
import gluegun/request.{
  type Stream, Connect, Custom, Delete, Get, Head, Options, Patch, Post, Put,
  Trace,
}

/// Alias for `gluegun/request.Method` used in decoded messages.
pub type Method =
  request.Method

/// Alias for `gluegun/request.Header` used in decoded messages.
pub type Header =
  request.Header

/// WebSocket frames delivered inside Gun stream messages.
///
/// On the wire Gun delivers `close` (atom) as `Close` and
/// `{close, Code, Reason}` as `CloseWithReason`.
pub type Frame {
  /// A UTF-8 text frame. Gun validates the payload as UTF-8 before delivery.
  Text(String)
  /// A binary frame. The payload is an opaque byte string.
  Binary(BitArray)
  /// A ping control frame. Reply with `Pong` to keep the connection alive.
  Ping(BitArray)
  /// A pong control frame. Usually delivered in response to a `Ping`.
  Pong(BitArray)
  /// A close control frame with no status code or reason.
  Close
  /// A close control frame carrying a numeric close code and opaque reason
  /// payload (RFC 6455 §5.5.1).
  CloseWithReason(code: Int, reason: BitArray)
}

/// Gun HTTP stream messages delivered by the Erlang Gun client.
///
/// Sequencing for a normal HTTP response:
/// zero or more `Inform` (1xx) → one `Response` → zero or more `Data` (until
/// `Fin`) → optional `Trailers`. `Push` and `Upgrade` may appear for HTTP/2
/// server push and protocol switching. `WebSocket` only appears after a
/// successful upgrade.
///
/// This type is closed; new variants are a breaking change. Pin to a major
/// version.
pub type Message {
  /// A 1xx informational response. May appear multiple times before the
  /// final `Response`.
  Inform(status: Int, headers: List(Header))
  /// The final HTTP response headers. `fin` is `Fin` when there is no body.
  Response(fin: Fin, status: Int, headers: List(Header))
  /// A response body chunk. `fin` is `Fin` on the last chunk.
  Data(fin: Fin, data: BitArray)
  /// Trailing headers delivered after the body (HTTP/1.1 trailers or HTTP/2
  /// trailer frames).
  Trailers(headers: List(Header))
  /// An HTTP/2 server push. The `stream` is a new stream the caller may
  /// await or cancel.
  Push(stream: Stream, method: Method, uri: String, headers: List(Header))
  /// A successful protocol upgrade. Subsequent messages on this stream use
  /// the new protocol (e.g. WebSocket).
  Upgrade(protocols: List(String), headers: List(Header))
  /// A decoded WebSocket frame. Only delivered after an upgrade.
  WebSocket(frame: Frame)
}

/// Alias for `gluegun/error.GluegunError`.
pub type GluegunError =
  error.GluegunError

/// Decode a raw Erlang Gun message into a typed Gleam message.
///
/// Useful when receiving Gun messages outside Gluegun's helpers (e.g. inside
/// a custom `receive` loop). Returns `DecodeError` if the dynamic value is
/// not a recognized Gun message shape.
pub fn decode(data: Dynamic) -> Result(Message, GluegunError) {
  dyn_decode.run(data, message_decoder())
  |> result.map_error(fn(_) { error.DecodeError("Invalid Gun message") })
}

/// Await the next Gun message for a stream.
///
/// Blocks the calling process until a message arrives, the stream errors,
/// or `timeout` elapses. Messages arrive in the order described on
/// `Message`: `Inform`* → `Response` → `Data`* → `Trailers`?. Use this for
/// streaming responses, server push, or any flow where you need messages as
/// they arrive.
///
/// Errors: `Timeout`, `ConnectionDown`, `StreamError`, `DecodeError`.
pub fn await(
  connection: Connection,
  stream: Stream,
  timeout: Timeout,
) -> Result(Message, GluegunError) {
  ffi_await(
    internal.connection_raw(connection),
    internal.stream_raw(stream),
    timeout_to_ffi(timeout),
  )
  |> result.map_error(error.decode_ffi_error)
  |> result.try(decode)
}

/// Await and collect the full response body for a stream.
///
/// Drains body chunks until the final `Fin` and returns the concatenated
/// payload. Headers must already have been consumed (e.g. via a prior
/// `await` that returned `Response`). For incremental access use `await`
/// directly. The full body is held in memory; use the lower-level loop for
/// very large responses.
///
/// Errors: `Timeout`, `ConnectionDown`, `StreamError`.
pub fn await_body(
  connection: Connection,
  stream: Stream,
  timeout: Timeout,
) -> Result(BitArray, GluegunError) {
  ffi_await_body(
    internal.connection_raw(connection),
    internal.stream_raw(stream),
    timeout_to_ffi(timeout),
  )
  |> result.map_error(error.decode_ffi_error)
}

fn message_decoder() -> dyn_decode.Decoder(Message) {
  use tag <- dyn_decode.field("type", dyn_decode.string)
  case tag {
    "inform" -> inform_decoder()
    "response" -> response_decoder()
    "data" -> data_decoder()
    "trailers" -> trailers_decoder()
    "push" -> push_decoder()
    "upgrade" -> upgrade_decoder()
    "websocket" -> websocket_decoder()
    "ws" -> websocket_decoder()
    _ -> fail_message_decode()
  }
}

fn fail_message_decode() -> dyn_decode.Decoder(Message) {
  dyn_decode.failure(message_decode_placeholder(), expected: "Message")
}

fn message_decode_placeholder() -> Message {
  Data(NoFin, <<"gluegun decode failure placeholder":utf8>>)
}

fn inform_decoder() -> dyn_decode.Decoder(Message) {
  use status <- dyn_decode.field("status", dyn_decode.int)
  use headers <- dyn_decode.field("headers", headers_decoder())
  dyn_decode.success(Inform(status, headers))
}

fn response_decoder() -> dyn_decode.Decoder(Message) {
  use fin <- dyn_decode.field("fin", fin_decoder())
  use status <- dyn_decode.field("status", dyn_decode.int)
  use headers <- dyn_decode.field("headers", headers_decoder())
  dyn_decode.success(Response(fin, status, headers))
}

fn data_decoder() -> dyn_decode.Decoder(Message) {
  use fin <- dyn_decode.field("fin", fin_decoder())
  use data <- dyn_decode.field("data", dyn_decode.bit_array)
  dyn_decode.success(Data(fin, data))
}

fn trailers_decoder() -> dyn_decode.Decoder(Message) {
  use headers <- dyn_decode.field("headers", headers_decoder())
  dyn_decode.success(Trailers(headers))
}

fn upgrade_decoder() -> dyn_decode.Decoder(Message) {
  use protocols <- dyn_decode.field(
    "protocols",
    dyn_decode.list(dyn_decode.string),
  )
  use headers <- dyn_decode.field("headers", headers_decoder())
  dyn_decode.success(Upgrade(protocols, headers))
}

fn push_decoder() -> dyn_decode.Decoder(Message) {
  use stream <- dyn_decode.field("stream", stream_decoder())
  use method <- dyn_decode.field("method", method_decoder())
  use uri <- dyn_decode.field("uri", dyn_decode.string)
  use headers <- dyn_decode.field("headers", headers_decoder())
  dyn_decode.success(Push(stream, method, uri, headers))
}

fn websocket_decoder() -> dyn_decode.Decoder(Message) {
  use frame <- dyn_decode.field("frame", frame_decoder())
  dyn_decode.success(WebSocket(frame))
}

fn stream_decoder() -> dyn_decode.Decoder(Stream) {
  dyn_decode.map(dyn_decode.dynamic, internal.stream)
}

fn method_decoder() -> dyn_decode.Decoder(Method) {
  dyn_decode.map(dyn_decode.string, fn(method) {
    case string.uppercase(method) {
      "GET" -> Get
      "HEAD" -> Head
      "POST" -> Post
      "PUT" -> Put
      "PATCH" -> Patch
      "DELETE" -> Delete
      "OPTIONS" -> Options
      "TRACE" -> Trace
      "CONNECT" -> Connect
      _ -> Custom(method)
    }
  })
}

fn frame_decoder() -> dyn_decode.Decoder(Frame) {
  use tag <- dyn_decode.field("type", dyn_decode.string)
  case tag {
    "text" -> text_frame_decoder()
    "binary" -> binary_frame_decoder()
    "close" -> dyn_decode.success(Close)
    "close_with_reason" -> close_with_reason_frame_decoder()
    "ping" -> ping_frame_decoder()
    "pong" -> pong_frame_decoder()
    _ -> fail_frame_decode()
  }
}

fn fail_frame_decode() -> dyn_decode.Decoder(Frame) {
  dyn_decode.failure(frame_decode_placeholder(), expected: "Frame")
}

fn frame_decode_placeholder() -> Frame {
  Text("gluegun decode failure placeholder")
}

fn text_frame_decoder() -> dyn_decode.Decoder(Frame) {
  use data <- dyn_decode.field("data", dyn_decode.string)
  dyn_decode.success(Text(data))
}

fn binary_frame_decoder() -> dyn_decode.Decoder(Frame) {
  use data <- dyn_decode.field("data", dyn_decode.bit_array)
  dyn_decode.success(Binary(data))
}

fn close_with_reason_frame_decoder() -> dyn_decode.Decoder(Frame) {
  use code <- dyn_decode.field("code", dyn_decode.int)
  use reason <- dyn_decode.field("reason", dyn_decode.bit_array)
  dyn_decode.success(CloseWithReason(code, reason))
}

fn ping_frame_decoder() -> dyn_decode.Decoder(Frame) {
  use data <- dyn_decode.field("data", dyn_decode.bit_array)
  dyn_decode.success(Ping(data))
}

fn pong_frame_decoder() -> dyn_decode.Decoder(Frame) {
  use data <- dyn_decode.field("data", dyn_decode.bit_array)
  dyn_decode.success(Pong(data))
}

fn fin_decoder() -> dyn_decode.Decoder(Fin) {
  dyn_decode.map(dyn_decode.bool, fn(fin) {
    case fin {
      True -> Fin
      False -> NoFin
    }
  })
}

fn headers_decoder() -> dyn_decode.Decoder(List(Header)) {
  dyn_decode.map(dyn_decode.list(header_decoder()), request.normalize_headers)
}

fn header_decoder() -> dyn_decode.Decoder(Header) {
  dyn_decode.then(dyn_decode.at([0], dyn_decode.string), fn(name) {
    dyn_decode.map(dyn_decode.at([1], dyn_decode.string), fn(value) {
      #(name, value)
    })
  })
}

@external(erlang, "gluegun_ffi", "await")
fn ffi_await(
  connection: Dynamic,
  stream: Dynamic,
  timeout: Dynamic,
) -> Result(Dynamic, Dynamic)

@external(erlang, "gluegun_ffi", "await_body")
fn ffi_await_body(
  connection: Dynamic,
  stream: Dynamic,
  timeout: Dynamic,
) -> Result(BitArray, Dynamic)
