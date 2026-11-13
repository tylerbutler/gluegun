import gleam/result
import gluegun/client
import gluegun/connection
import gluegun/error
import gluegun/response

pub fn get_over_http2() -> Result(
  response.Response(BitArray),
  error.GluegunError,
) {
  use timeout <- result.try(connection.milliseconds(5000))
  let options =
    connection.options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.with_protocols(protocols: [connection.Http2, connection.Http1])

  run("example.com", 443, options, timeout)
}

pub fn run(
  host: String,
  port: Int,
  options: connection.ConnectOptions,
  timeout: connection.Timeout,
) -> Result(response.Response(BitArray), error.GluegunError) {
  use conn <- result.try(connection.open(options, host: host, port: port))
  let exchange = {
    use _protocol <- result.try(connection.await_up(conn, timeout))
    client.get(conn, "/", [], timeout)
  }
  let cleanup = connection.terminate(conn)
  finish(exchange, cleanup)
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
