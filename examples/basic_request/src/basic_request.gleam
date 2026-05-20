/// Basic HTTP GET example using gluegun.
///
/// This source file is documentation-only in this repository. Copy it into a
/// Gleam project that depends on gluegun to run it.
import gleam/int
import gleam/io
import gluegun/client
import gluegun/connection
import gluegun/error
import gluegun/response

const host = "example.com"

const port = 80

const path = "/"

pub fn main() {
  let timeout = connection.Milliseconds(5000)

  case connection.options() |> connection.open(host: host, port: port) {
    Ok(conn) -> {
      let assert Ok(_protocol) = connection.await_up(conn, timeout)

      case client.get(conn, path, [], timeout) {
        Ok(res) -> print_response(res)
        Error(err) -> io.println("request failed: " <> error_to_string(err))
      }

      let assert Ok(Nil) = connection.close(conn)
    }

    Error(err) -> io.println("connection failed: " <> error_to_string(err))
  }
}

fn print_response(res) {
  io.println("status: " <> int.to_string(response.status(res)))

  case response.body_text(res) {
    Ok(text) -> io.println(text)
    Error(_) -> io.println("response body was not valid UTF-8")
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
    error.UnsupportedFeature(reason) -> "unsupported feature: " <> reason
    error.ErlangError(reason) -> "erlang error: " <> reason
    error.DecodeError(reason) -> "decode error: " <> reason
  }
}
