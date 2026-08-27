/// Basic HTTP GET example using Gluegun.
///
/// Buildable basic HTTP request example.
import gleam/int
import gleam/io
import gluegun/client
import gluegun/connection
import gluegun/error
import gluegun/response

const host = "example.com"

const port = 80

const path = "/"

pub fn main() -> Nil {
  let timeout = connection.Milliseconds(5000)

  case connection.options() |> connection.open(host: host, port: port) {
    Ok(connection) -> {
      let assert Ok(protocol) = connection.await_up(connection, timeout)
      io.println("protocol: " <> protocol_to_string(protocol))

      case client.get(connection, path, [], timeout) {
        Ok(response) -> print_response(response)
        Error(error) -> io.println("request failed: " <> error_to_string(error))
      }

      let assert Ok(Nil) = connection.close(connection)
      Nil
    }

    Error(error) -> io.println("connection failed: " <> error_to_string(error))
  }
}

fn print_response(response: response.Response) -> Nil {
  io.println("status: " <> int.to_string(response.status(response)))

  case response.body_text(response) {
    Ok(text) -> io.println(text)
    Error(_) -> io.println("response body was not valid UTF-8")
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
    error.UnsupportedFeature(reason) -> "unsupported feature: " <> reason
    error.ErlangError(reason) -> "erlang error: " <> reason
    error.DecodeError(reason) -> "decode error: " <> reason
  }
}
