import gleam/dynamic.{type Dynamic}

pub opaque type Connection {
  Connection(raw: Dynamic)
}

pub opaque type Stream {
  Stream(raw: Dynamic)
}

@internal
pub fn connection(raw: Dynamic) -> Connection {
  Connection(raw: raw)
}

@internal
pub fn connection_raw(connection: Connection) -> Dynamic {
  connection.raw
}

@internal
pub fn stream(raw: Dynamic) -> Stream {
  Stream(raw: raw)
}

@internal
pub fn stream_raw(stream: Stream) -> Dynamic {
  stream.raw
}
