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

pub fn main() {
  let timeout = connection.Milliseconds(15_000)

  case
    connection.options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.open(host: host, port: port)
  {
    Ok(conn) -> {
      case download(conn, timeout) {
        Ok(Nil) -> Nil
        Error(err) -> io.println("download failed: " <> error_to_string(err))
      }

      close(conn)
    }

    Error(err) -> io.println("connection failed: " <> error_to_string(err))
  }
}

fn download(conn, timeout) {
  use protocol <- result.try(connection.await_up(conn, timeout))
  io.println("protocol: " <> protocol_to_string(protocol))

  use stream <- result.try(request.request(
    conn,
    request.Get,
    path,
    [],
    <<>>,
    request.options(),
  ))

  await_response(conn, stream, timeout)
}

fn await_response(conn, stream, timeout) {
  case message.await(conn, stream, timeout) {
    Ok(message.Response(response_fin, status, headers)) -> {
      io.println("status: " <> int.to_string(status))
      io.println("headers: " <> int.to_string(count(headers)))

      case response_fin {
        fin.Fin -> Ok(Nil)
        fin.NoFin -> stream_body(conn, stream, timeout)
      }
    }

    Ok(other) -> unexpected(other)
    Error(err) -> Error(err)
  }
}

fn stream_body(conn, stream, timeout) {
  case message.await(conn, stream, timeout) {
    Ok(message.Data(fin.NoFin, data)) -> {
      print_chunk(data)
      stream_body(conn, stream, timeout)
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
    Error(err) -> Error(err)
  }
}

fn print_chunk(data: BitArray) {
  io.println("chunk bytes: " <> int.to_string(bit_array.byte_size(data)))
}

fn close(conn) {
  case connection.close(conn) {
    Ok(Nil) -> Nil
    Error(err) -> io.println("close failed: " <> error_to_string(err))
  }
}

fn unexpected(msg: message.Message) -> Result(Nil, error.GluegunError) {
  Error(error.InvalidMessage("unexpected message: " <> message_to_string(msg)))
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

fn message_to_string(msg: message.Message) -> String {
  case msg {
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

fn error_to_string(err: error.GluegunError) -> String {
  case err {
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
