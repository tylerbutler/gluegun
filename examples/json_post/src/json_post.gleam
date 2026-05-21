/// JSON POST example using gluegun's high-level HTTP client API.
///
/// Buildable JSON POST example.
import gleam/int
import gleam/io
import gleam/list
import gluegun/client
import gluegun/connection
import gluegun/error
import gluegun/request
import gluegun/response

const host = "httpbingo.org"

const port = 80

const path = "/post"

pub fn main() {
  let timeout = connection.Milliseconds(15_000)

  case connection.options() |> connection.open(host: host, port: port) {
    Ok(conn) -> {
      case connection.await_up(conn, timeout) {
        Ok(protocol) -> {
          io.println("protocol: " <> protocol_to_string(protocol))

          client.new(request.Post, path)
          |> client.with_header(name: "content-type", value: "application/json")
          |> client.with_header(name: "accept", value: "application/json")
          |> client.with_header(
            name: "user-agent",
            value: "gluegun-json-post/0.1.0",
          )
          |> client.with_body(body: <<"{ \"name\": \"widget\" }":utf8>>)
          |> client.with_timeout(timeout: timeout)
          |> client.send(connection: conn)
          |> print_result
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

fn print_result(result) {
  case result {
    Ok(res) -> print_response(res)
    Error(err) -> io.println("request failed: " <> error_to_string(err))
  }
}

fn print_response(res) {
  io.println("status: " <> int.to_string(response.status(res)))
  io.println(
    "response header count: "
    <> int.to_string(list.length(response.headers(res))),
  )

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
