import gleam/http
import gleam/list
import gleam/option.{Some}
import gleam/result
import gluegun
import gluegun/client
import gluegun/connection
import gluegun/error
import gluegun/message
import gluegun/response
import gluegun/websocket

pub fn main() {
  let assert Ok(Nil) =
    with_server(fn(port) {
      use timeout <- result.try(gluegun.milliseconds(2000))
      use conn <- result.try(
        gluegun.connection_options()
        |> gluegun.open(host: "127.0.0.1", port: port),
      )
      let exchange = {
        use _ <- result.try(gluegun.await_up(conn, timeout))
        use res <- result.try(
          gluegun.new_request(http.Get, "/")
          |> gluegun.send(connection: conn),
        )
        let assert 200 = response.status(res)
        let assert Ok("hello") = gluegun.body_text(res)
        let assert [#("x-check", "done")] = response.trailers(res)
        let assert [response.Informational(103, _)] =
          response.informational(res)
        use next <- result.try(client.options(
          conn,
          path: "/",
          headers: [],
          timeout: timeout,
        ))
        let assert 204 = response.status(next)
        Ok(Nil)
      }
      let cleanup = gluegun.terminate(conn)
      use _ <- result.try(exchange)
      cleanup
    })
  let assert Ok(Nil) = with_websocket_server(websocket_roundtrip)
  let assert Ok(Nil) =
    with_websocket_server(fn(port) {
      use timeout <- result.try(connection.milliseconds(2000))
      use conn <- result.try(
        connection.options() |> connection.open(host: "127.0.0.1", port: port),
      )
      let exchange = {
        use protocol <- result.try(connection.await_up(conn, timeout))
        use socket <- result.try(adopt(conn, protocol, timeout))
        let outcome = check_socket(socket)
        let cleanup = websocket.close(socket)
        use _ <- result.try(outcome)
        cleanup
      }
      let cleanup = connection.terminate(conn)
      use _ <- result.try(exchange)
      cleanup
    })
  Nil
}

/// Exercise finite-credit close after coalesced queued application frames.
pub fn websocket_roundtrip(port: Int) -> Result(Nil, error.GluegunError) {
  use upgrade <- result.try(upgrade_options())
  websocket.with_socket(
    host: "127.0.0.1",
    port: port,
    path: "/",
    options: websocket.options() |> websocket.with_upgrade_options(upgrade),
    callback: check_socket,
  )
}

fn check_socket(socket: websocket.Socket) -> Result(Nil, error.GluegunError) {
  let assert Some("chat") = websocket.selected_subprotocol(socket)
  let headers = websocket.handshake(socket) |> websocket.handshake_headers
  let assert True = list.contains(headers, #("x-handshake", "yes"))
  use _ <- result.try(websocket.send_text(socket, "hello"))
  use frame <- result.try(websocket.receive_frame(socket))
  let assert message.Text("hello") = frame
  Ok(Nil)
}

fn upgrade_options() {
  websocket.upgrade_options()
  |> websocket.with_subprotocols(["chat"])
  |> websocket.with_flow(1)
}

/// Exercise public low-level adoption and negotiated protocol checking.
pub fn adopt(
  conn: connection.Connection,
  protocol: connection.Protocol,
  timeout: connection.Timeout,
) {
  use options <- result.try(upgrade_options())
  use stream <- result.try(websocket.upgrade(conn, protocol, "/", [], options))
  use handshake <- result.try(websocket.await_upgrade(conn, stream, timeout))
  Ok(websocket.from_upgrade(conn, stream, handshake, timeout))
}

@external(erlang, "compatibility_peer", "with_server")
fn with_server(
  callback: fn(Int) -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

@external(erlang, "compatibility_peer", "with_websocket_server")
fn with_websocket_server(
  callback: fn(Int) -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)
