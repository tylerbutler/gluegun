import gleam/dynamic
import gluegun
import gluegun/client
import gluegun/connection
import gluegun/internal
import gluegun/request
import gluegun/websocket
import startest.{describe, it}
import startest/expect

pub fn main() -> Nil {
  startest.run(startest.default_config())
}

pub fn gluegun_tests() {
  describe("gluegun root facade", [
    it("builds a root request with default fields", fn() {
      gluegun.new_request(request.Get, "/")
      |> client.inspect_request
      |> expect.to_equal(client.RequestFields(
        method: request.Get,
        path: "/",
        headers: [],
        body: <<>>,
        options: request.options(),
        timeout: connection.Milliseconds(5000),
      ))
    }),
    it("exposes root WebSocket options", fn() {
      gluegun.websocket_options()
      |> websocket.options_timeout
      |> expect.to_equal(connection.Milliseconds(5000))
    }),
    it("exposes the minimal common-path root helpers", fn() {
      compile_common_path_facade(False)
      |> expect.to_equal(Nil)
    }),
    it("exposes public handle types from non-internal modules", fn() {
      compile_public_handle_types(False)
      |> expect.to_equal(Nil)
    }),
  ])
}

fn compile_common_path_facade(should_run: Bool) -> Nil {
  case should_run {
    True -> {
      let assert Ok(conn) =
        gluegun.open(
          gluegun.connection_options(),
          host: "localhost",
          port: 8080,
        )
      let assert Ok(_protocol) =
        gluegun.await_up(conn, connection.Milliseconds(5000))
      let request = gluegun.new_request(request.Get, "/")
      let assert Ok(response) = gluegun.send(request, connection: conn)
      let assert Ok(_body) = gluegun.body_text(response)
      let assert Ok(_socket) =
        gluegun.websocket_connect(
          host: "localhost",
          port: 8080,
          path: "/echo",
          options: gluegun.websocket_options(),
        )
      Nil
    }
    False -> Nil
  }
}

fn compile_public_handle_types(should_run: Bool) -> Nil {
  case should_run {
    True -> {
      let connection = internal.connection(dynamic.string("connection"))
      let stream = internal.stream(dynamic.string("stream"))
      let _ = accept_connection(connection)
      let _ = accept_stream(stream)
      Nil
    }
    False -> Nil
  }
}

fn accept_connection(_connection: connection.Connection) -> Nil {
  Nil
}

fn accept_stream(_stream: request.Stream) -> Nil {
  Nil
}
