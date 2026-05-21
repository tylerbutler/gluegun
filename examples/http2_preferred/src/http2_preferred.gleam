/// HTTP/2 preference example using Gluegun's high-level HTTP client API.
///
/// Buildable example that prefers HTTP/2 over TLS and falls back to HTTP/1.1.
import gleam/int
import gleam/io
import gluegun/client
import gluegun/connection
import gluegun/error
import gluegun/response

const host = "nghttp2.org"

const port = 443

const path = "/httpbin/get"

pub fn main() {
  let timeout = connection.Milliseconds(15_000)
  let options =
    connection.options()
    |> connection.with_transport(connection.Tls)
    |> connection.with_protocols([connection.Http2, connection.Http1])

  case connection.open(options, host: host, port: port) {
    Ok(conn) -> {
      case connection.await_up(conn, timeout) {
        Ok(protocol) -> {
          io.println("protocol: " <> protocol_to_string(protocol))

          case client.get(conn, path, [], timeout) {
            Ok(res) -> print_response(res)
            Error(err) -> io.println("request failed: " <> error_to_string(err))
          }
        }

        Error(err) -> io.println("connection failed: " <> error_to_string(err))
      }

      case connection.close(conn) {
        Ok(Nil) -> Nil
        Error(err) -> io.println("close failed: " <> error_to_string(err))
      }
    }

    Error(err) -> io.println("connection failed: " <> error_to_string(err))
  }
}

fn print_response(res) {
  io.println("status: " <> int.to_string(response.status(res)))

  case response.body_text(res) {
    Ok(text) -> io.println(text)
    Error(err) ->
      io.println("response body failed UTF-8 decode: " <> error_to_string(err))
  }
}

fn protocol_to_string(protocol: connection.Protocol) -> String {
  case protocol {
    connection.Http1 -> "HTTP/1.1"
    connection.Http2 -> "HTTP/2"
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
