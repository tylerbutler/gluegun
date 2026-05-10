import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode as dyn_decode
import gleam/result
import gleam/string
import gluegun/error
import gluegun/internal.{type Connection, type Stream}
import gluegun/request.{type Header, type Method, normalize_headers}

pub type Fin {
  Fin
  NoFin
}

/// WebSocket frames delivered inside Gun stream messages.
pub type Frame {
  Text(String)
  Binary(BitArray)
  Close(Int, String)
  Ping(BitArray)
  Pong(BitArray)
}

/// Gun HTTP stream messages delivered by the Erlang Gun client.
pub type Message {
  Inform(status: Int, headers: List(Header))
  Response(fin: Fin, status: Int, headers: List(Header))
  Data(fin: Fin, data: BitArray)
  Trailers(headers: List(Header))
  Push(stream: Stream, method: Method, uri: String, headers: List(Header))
  Upgrade(protocols: List(String), headers: List(Header))
  WebSocket(frame: Frame)
}

pub type GluegunError =
  error.GluegunError

pub fn decode(data: Dynamic) -> Result(Message, GluegunError) {
  dyn_decode.run(data, message_decoder())
  |> result.map_error(fn(_) { error.DecodeError("Invalid Gun message") })
}

pub fn decode_ffi_error(error: Dynamic) -> GluegunError {
  error.decode_ffi_error(error)
}

/// Await the next Gun message for a stream.
pub fn await(
  connection: Connection,
  stream: Stream,
  timeout: anything,
) -> Result(Message, GluegunError) {
  ffi_await(
    internal.connection_raw(connection),
    internal.stream_raw(stream),
    unsafe_coerce(timeout),
  )
  |> result.map_error(error.decode_ffi_error)
  |> result.try(decode)
}

/// Await and collect the full response body for a stream.
pub fn await_body(
  connection: Connection,
  stream: Stream,
  timeout: anything,
) -> Result(BitArray, GluegunError) {
  ffi_await_body(
    internal.connection_raw(connection),
    internal.stream_raw(stream),
    unsafe_coerce(timeout),
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
      "GET" -> request.Get
      "HEAD" -> request.Head
      "POST" -> request.Post
      "PUT" -> request.Put
      "PATCH" -> request.Patch
      "DELETE" -> request.Delete
      "OPTIONS" -> request.Options
      "TRACE" -> request.Trace
      "CONNECT" -> request.Connect
      _ -> request.Custom(method)
    }
  })
}

fn frame_decoder() -> dyn_decode.Decoder(Frame) {
  use tag <- dyn_decode.field("type", dyn_decode.string)
  case tag {
    "text" -> text_frame_decoder()
    "binary" -> binary_frame_decoder()
    "close" -> close_frame_decoder()
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

fn close_frame_decoder() -> dyn_decode.Decoder(Frame) {
  use code <- dyn_decode.field("code", dyn_decode.int)
  use reason <- dyn_decode.field("reason", dyn_decode.string)
  dyn_decode.success(Close(code, reason))
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
  dyn_decode.map(dyn_decode.list(header_decoder()), normalize_headers)
}

fn header_decoder() -> dyn_decode.Decoder(Header) {
  dyn_decode.then(dyn_decode.at([0], dyn_decode.string), fn(name) {
    dyn_decode.map(dyn_decode.at([1], dyn_decode.string), fn(value) {
      #(name, value)
    })
  })
}

@external(erlang, "gleam_stdlib", "identity")
fn unsafe_coerce(a: anything) -> Dynamic

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
