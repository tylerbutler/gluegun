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

pub fn main() -> Nil {
  let timeout = connection.Milliseconds(15_000)
  let options =
    connection.options()
    |> connection.with_transport(connection.Tls)
    |> connection.with_protocols([connection.Http2, connection.Http1])

  case connection.open(options, host: host, port: port) {
    Ok(connection) -> {
      case connection.await_up(connection, timeout) {
        Ok(protocol) -> {
          io.println("protocol: " <> protocol_to_string(protocol))

          case client.get(connection, path, [], timeout) {
            Ok(response) -> print_response(response)
            Error(error) ->
              io.println("request failed: " <> error_to_string(error))
          }
        }

        Error(error) ->
          io.println("connection failed: " <> error_to_string(error))
      }

      case connection.close(connection) {
        Ok(Nil) -> Nil
        Error(error) -> io.println("close failed: " <> error_to_string(error))
      }
    }

    Error(error) -> io.println("connection failed: " <> error_to_string(error))
  }
}

fn print_response(response: response.Response) -> Nil {
  io.println("status: " <> int.to_string(response.status(response)))

  case response.body_text(response) {
    Ok(text) -> io.println(text)
    Error(error) ->
      io.println(
        "response body failed UTF-8 decode: " <> error_to_string(error),
      )
  }
}

fn protocol_to_string(protocol: connection.Protocol) -> String {
  case protocol {
    connection.Http1 -> "HTTP/1.1"
    connection.Http2 -> "HTTP/2"
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
