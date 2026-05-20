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

pub fn main() {
  let timeout = connection.Milliseconds(15_000)

  case
    connection.options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.open(host: host, port: port)
  {
    Ok(conn) -> {
      case connection.await_up(conn, timeout) {
        Ok(protocol) -> {
          io.println("protocol: " <> protocol_to_string(protocol))
          upload_chunks(conn, timeout)
        }

        Error(err) -> io.println("connection failed: " <> error_to_string(err))
      }

      close(conn)
    }

    Error(err) -> io.println("connection failed: " <> error_to_string(err))
  }
}

fn upload_chunks(conn, timeout) {
  case
    request.headers(
      conn,
      request.Post,
      path,
      [#("content-type", "text/plain")],
      request.options(),
    )
  {
    Ok(stream) -> {
      case send_chunks(conn, stream) {
        Ok(Nil) -> await_response(conn, stream, timeout)
        Error(err) -> io.println("upload failed: " <> error_to_string(err))
      }
    }

    Error(err) -> io.println("request failed: " <> error_to_string(err))
  }
}

fn send_chunks(conn, stream) {
  use _ <- result.try(
    request.data(conn, stream, fin.NoFin, <<"first chunk\n":utf8>>),
  )
  use _ <- result.try(
    request.data(conn, stream, fin.NoFin, <<"second chunk\n":utf8>>),
  )
  request.data(conn, stream, fin.Fin, <<"final chunk\n":utf8>>)
}

fn await_response(conn, stream, timeout) {
  case message.await(conn, stream, timeout) {
    Ok(message.Inform(status, _headers)) -> {
      io.println("informational status: " <> int.to_string(status))
      await_response(conn, stream, timeout)
    }

    Ok(message.Response(response_fin, status, _headers)) -> {
      case response_fin {
        fin.Fin -> io.println("final status: " <> int.to_string(status))
        fin.NoFin -> {
          case message.await_body(conn, stream, timeout) {
            Ok(_body) -> io.println("final status: " <> int.to_string(status))
            Error(err) ->
              io.println("response body failed: " <> error_to_string(err))
          }
        }
      }
    }

    Ok(other) -> io.println("unexpected message: " <> message_to_string(other))
    Error(err) -> io.println("response failed: " <> error_to_string(err))
  }
}

fn close(conn) {
  case connection.close(conn) {
    Ok(Nil) -> Nil
    Error(err) -> io.println("close failed: " <> error_to_string(err))
  }
}

fn protocol_to_string(protocol: connection.Protocol) -> String {
  case protocol {
    connection.Http1 -> "HTTP/1.1"
    connection.Http2 -> "HTTP/2"
  }
}

fn message_to_string(msg: message.Message) -> String {
  case msg {
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
  }
}
