import gleam/http
import gleam/int
import gleam/io
import gleam/result
import gluegun/client
import gluegun/connection
import gluegun/error
import gluegun/response

pub fn main() -> Result(Nil, error.GluegunError) {
  use timeout <- result.try(connection.milliseconds(5000))
  run("example.com", 80, connection.options(), timeout)
}

pub fn run(
  host: String,
  port: Int,
  options: connection.ConnectOptions,
  timeout: connection.Timeout,
) -> Result(Nil, error.GluegunError) {
  use conn <- result.try(connection.open(options, host: host, port: port))
  let exchange = {
    use _protocol <- result.try(connection.await_up(conn, timeout))
    client.new(http.Get, "/")
    |> client.with_timeout(timeout: timeout)
    |> client.send(connection: conn)
  }
  let cleanup = connection.terminate(conn)
  use res <- result.try(finish(exchange, cleanup))

  io.println("status: " <> int.to_string(res.response.status))

  case response.body_text(res) {
    Ok(text) -> io.println(text)
    Error(_) -> io.println("response body was not UTF-8")
  }

  Ok(Nil)
}

@internal
pub fn finish(
  exchange: Result(a, error.GluegunError),
  cleanup: Result(Nil, error.GluegunError),
) -> Result(a, error.GluegunError) {
  use value <- result.try(exchange)
  use _ <- result.try(cleanup)
  Ok(value)
}
