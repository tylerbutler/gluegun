import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode as dyn_decode
import gleam/result
import gluegun/internal.{type Stream}
import gluegun/request.{type Header, type Method, normalize_headers}

pub type Fin {
  Fin
  NoFin
}

pub type Frame {
  Text(String)
  Binary(BitArray)
  Close(Int, String)
  Ping(BitArray)
  Pong(BitArray)
}

pub type Message {
  Inform(status: Int, headers: List(Header))
  Response(fin: Fin, status: Int, headers: List(Header))
  Data(fin: Fin, data: BitArray)
  Trailers(headers: List(Header))
  Push(stream: Stream, method: Method, uri: String, headers: List(Header))
  Upgrade(protocols: List(String), headers: List(Header))
  WebSocket(frame: Frame)
}

pub type GluegunError {
  DecodeError(String)
}

pub fn decode(data: Dynamic) -> Result(Message, GluegunError) {
  dyn_decode.run(data, message_decoder())
  |> result.map_error(fn(_) { DecodeError("Invalid Gun message") })
}

fn message_decoder() -> dyn_decode.Decoder(Message) {
  use tag <- dyn_decode.field("type", dyn_decode.string)
  case tag {
    "inform" -> inform_decoder()
    "response" -> response_decoder()
    "data" -> data_decoder()
    "trailers" -> trailers_decoder()
    "upgrade" -> upgrade_decoder()
    _ -> dyn_decode.failure(Data(NoFin, <<>>), expected: "Message")
  }
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
