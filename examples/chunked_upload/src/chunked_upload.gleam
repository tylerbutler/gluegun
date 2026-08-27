/// Low-level chunked request-body upload example using Gluegun.
///
/// Buildable chunked upload example.
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

const path = "/post"

pub fn main() -> Nil {
  let timeout = connection.Milliseconds(15_000)

  case
    connection.options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.open(host: host, port: port)
  {
    Ok(connection) -> {
      case connection.await_up(connection, timeout) {
        Ok(protocol) -> {
          io.println("protocol: " <> protocol_to_string(protocol))
          upload_chunks(connection, timeout)
        }

        Error(error) ->
          io.println("connection failed: " <> error_to_string(error))
      }

      close(connection)
    }

    Error(error) -> io.println("connection failed: " <> error_to_string(error))
  }
}

fn upload_chunks(
  connection: connection.Connection,
  timeout: connection.Timeout,
) -> Nil {
  case
    request.start_stream(
      connection,
      request.Post,
      path,
      [#("content-type", "text/plain")],
      request.options(),
    )
  {
    Ok(stream) -> {
      case send_chunks(connection, stream) {
        Ok(Nil) -> await_response(connection, stream, timeout)
        Error(error) -> io.println("upload failed: " <> error_to_string(error))
      }
    }

    Error(error) -> io.println("request failed: " <> error_to_string(error))
  }
}

fn send_chunks(
  connection: connection.Connection,
  stream: request.Stream,
) -> Result(Nil, error.GluegunError) {
  use _ <- result.try(
    request.data(connection, stream, fin.NoFin, <<"first chunk\n":utf8>>),
  )
  use _ <- result.try(
    request.data(connection, stream, fin.NoFin, <<"second chunk\n":utf8>>),
  )
  request.data(connection, stream, fin.Fin, <<"final chunk\n":utf8>>)
}

fn await_response(
  connection: connection.Connection,
  stream: request.Stream,
  timeout: connection.Timeout,
) -> Nil {
  case message.await(connection, stream, timeout) {
    Ok(message.Inform(status, _headers)) -> {
      io.println("informational status: " <> int.to_string(status))
      await_response(connection, stream, timeout)
    }

    Ok(message.Response(response_fin, status, _headers)) -> {
      case response_fin {
        fin.Fin -> io.println("final status: " <> int.to_string(status))
        fin.NoFin -> {
          case message.await_body(connection, stream, timeout) {
            Ok(_body) -> io.println("final status: " <> int.to_string(status))
            Error(error) ->
              io.println("response body failed: " <> error_to_string(error))
          }
        }
      }
    }

    Ok(other) -> io.println("unexpected message: " <> message_to_string(other))
    Error(error) -> io.println("response failed: " <> error_to_string(error))
  }
}

fn close(connection: connection.Connection) -> Nil {
  case connection.close(connection) {
    Ok(Nil) -> Nil
    Error(error) -> io.println("close failed: " <> error_to_string(error))
  }
}

fn protocol_to_string(protocol: connection.Protocol) -> String {
  case protocol {
    connection.Http1 -> "HTTP/1.1"
    connection.Http2 -> "HTTP/2"
  }
}

fn message_to_string(message: message.Message) -> String {
  case message {
    message.Inform(status, _) -> "Inform(" <> int.to_string(status) <> ")"
    message.Response(_, status, _) ->
      "Response(" <> int.to_string(status) <> ")"
    message.Data(_, _) -> "Data"
    message.Trailers(_) -> "Trailers"
    message.Push(_, method, uri, _) ->
      "Push(" <> request.method_to_string(method) <> " " <> uri <> ")"
    message.Upgrade(protocols, _) ->
      "Upgrade(" <> int.to_string(list.length(protocols)) <> " protocols)"
    message.WebSocket(_) -> "WebSocket"
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
