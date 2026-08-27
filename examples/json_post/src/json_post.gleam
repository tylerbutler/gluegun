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

pub fn main() -> Nil {
  let timeout = connection.Milliseconds(15_000)

  case connection.options() |> connection.open(host: host, port: port) {
    Ok(connection) -> {
      case connection.await_up(connection, timeout) {
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
          |> client.send(connection: connection)
          |> print_result
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

fn print_result(result: Result(response.Response, error.GluegunError)) -> Nil {
  case result {
    Ok(response) -> print_response(response)
    Error(error) -> io.println("request failed: " <> error_to_string(error))
  }
}

fn print_response(response: response.Response) -> Nil {
  io.println("status: " <> int.to_string(response.status(response)))
  io.println(
    "response header count: "
    <> int.to_string(list.length(response.headers(response))),
  )

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
