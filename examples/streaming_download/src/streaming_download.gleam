/// Low-level response-body streaming download example using Gluegun.
///
/// Buildable streaming download example.
import gleam/bit_array
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/message
import gluegun/request

const host = "httpbin.org"

const port = 443

const path = "/stream/5"

pub fn main() -> Nil {
  let timeout = connection.Milliseconds(15_000)

  case
    connection.options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.open(host: host, port: port)
  {
    Ok(connection) -> {
      case download(connection, timeout) {
        Ok(Nil) -> Nil
        Error(error) ->
          io.println("download failed: " <> error_to_string(error))
      }

      close(connection)
    }

    Error(error) -> io.println("connection failed: " <> error_to_string(error))
  }
}

fn download(
  connection: connection.Connection,
  timeout: connection.Timeout,
) -> Result(Nil, error.GluegunError) {
  use protocol <- result.try(connection.await_up(connection, timeout))
  io.println("protocol: " <> protocol_to_string(protocol))

  use stream <- result.try(request.request(
    connection,
    request.Get,
    path,
    [],
    <<>>,
    request.options(),
  ))

  await_response(connection, stream, timeout)
}

fn await_response(
  connection: connection.Connection,
  stream: request.Stream,
  timeout: connection.Timeout,
) -> Result(Nil, error.GluegunError) {
  case message.await(connection, stream, timeout) {
    Ok(message.Response(response_fin, status, headers)) -> {
      io.println("status: " <> int.to_string(status))
      io.println("headers: " <> int.to_string(count(headers)))

      case response_fin {
        fin.Fin -> Ok(Nil)
        fin.NoFin -> stream_body(connection, stream, timeout)
      }
    }

    Ok(other) -> unexpected(other)
    Error(error) -> Error(error)
  }
}

fn stream_body(
  connection: connection.Connection,
  stream: request.Stream,
  timeout: connection.Timeout,
) -> Result(Nil, error.GluegunError) {
  case message.await(connection, stream, timeout) {
    Ok(message.Data(fin.NoFin, data)) -> {
      print_chunk(data)
      stream_body(connection, stream, timeout)
    }

    Ok(message.Data(fin.Fin, data)) -> {
      print_chunk(data)
      Ok(Nil)
    }

    Ok(message.Trailers(headers)) -> {
      io.println("trailers: " <> int.to_string(count(headers)))
      Ok(Nil)
    }

    Ok(other) -> unexpected(other)
    Error(error) -> Error(error)
  }
}

fn print_chunk(data: BitArray) -> Nil {
  io.println("chunk bytes: " <> int.to_string(bit_array.byte_size(data)))
}

fn close(connection: connection.Connection) -> Nil {
  case connection.close(connection) {
    Ok(Nil) -> Nil
    Error(error) -> io.println("close failed: " <> error_to_string(error))
  }
}

fn unexpected(message: message.Message) -> Result(Nil, error.GluegunError) {
  Error(error.InvalidMessage(
    "unexpected message: " <> message_to_string(message),
  ))
}

fn protocol_to_string(protocol: connection.Protocol) -> String {
  case protocol {
    connection.Http1 -> "HTTP/1.1"
    connection.Http2 -> "HTTP/2"
  }
}

fn count(items: List(a)) -> Int {
  list.length(items)
}

fn message_to_string(message: message.Message) -> String {
  case message {
    message.Inform(status, _) -> "Inform(" <> int.to_string(status) <> ")"
    message.Response(_, status, _) ->
      "Response(" <> int.to_string(status) <> ")"
    message.Data(_, data) ->
      "Data(" <> int.to_string(bit_array.byte_size(data)) <> " bytes)"
    message.Trailers(headers) ->
      "Trailers(" <> int.to_string(count(headers)) <> " headers)"
    message.Push(_, method, uri, _) ->
      "Push(" <> request.method_to_string(method) <> " " <> uri <> ")"
    message.Upgrade(protocols, _) ->
      "Upgrade(" <> int.to_string(count(protocols)) <> " protocols)"
    message.WebSocket(frame) -> "WebSocket(" <> frame_to_string(frame) <> ")"
  }
}

fn frame_to_string(frame: message.Frame) -> String {
  case frame {
    message.Text(_) -> "Text"
    message.Binary(data) ->
      "Binary(" <> int.to_string(bit_array.byte_size(data)) <> " bytes)"
    message.Ping(data) ->
      "Ping(" <> int.to_string(bit_array.byte_size(data)) <> " bytes)"
    message.Pong(data) ->
      "Pong(" <> int.to_string(bit_array.byte_size(data)) <> " bytes)"
    message.Close -> "Close"
    message.CloseWithReason(code, reason) ->
      "CloseWithReason("
      <> int.to_string(code)
      <> ", "
      <> int.to_string(bit_array.byte_size(reason))
      <> " bytes)"
  }
}

fn error_to_string(error: error.GluegunError) -> String {
  case error {
    error.Timeout -> "timeout"
    error.ConnectionDown(reason) -> "connection down: " <> reason
    error.ConnectionError(reason) -> "connection error: " <> reason
    error.StreamError(reason) -> "stream error: " <> reason
    error.InvalidOptions(reason) -> "invalid options: " <> reason
    error.InvalidMessage(reason) -> "invalid message: " <> reason
    error.ErlangError(reason) -> "erlang error: " <> reason
    error.DecodeError(reason) -> "decode error: " <> reason
    error.UnsupportedFeature(reason) -> "unsupported feature: " <> reason
  }
}
