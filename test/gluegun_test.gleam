import gluegun
import gluegun/client
import gluegun/connection
import gluegun/request
import gluegun/websocket
import startest.{describe, it}
import startest/expect

pub fn main() -> Nil {
  startest.run(startest.default_config())
}

pub fn gluegun_tests() {
  describe("gluegun root facade", [
    it("returns the package name", fn() {
      gluegun.name()
      |> expect.to_equal("gluegun")
    }),
    it("builds a root request with default fields", fn() {
      gluegun.request(request.Get, "/")
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
    it("exposes root WebSocket helper names", fn() {
      compile_websocket_facade_helpers(False)
      |> expect.to_equal(Nil)
    }),
  ])
}

fn compile_websocket_facade_helpers(should_run: Bool) -> Nil {
  case should_run {
    True -> {
      let options = gluegun.websocket_options()
      let assert Ok(socket) =
        gluegun.websocket_connect(
          host: "localhost",
          port: 8080,
          path: "/echo",
          options: options,
        )
      let assert Ok(Nil) = gluegun.websocket_send_text(socket, "hello")
      let assert Ok(_) = gluegun.websocket_receive_app_frame(socket)
      let assert Ok(Nil) = gluegun.websocket_close(socket)
      let assert Ok(Nil) =
        gluegun.websocket_with_socket(
          host: "localhost",
          port: 8080,
          path: "/echo",
          options: options,
          callback: fn(socket) { gluegun.websocket_send_text(socket, "hello") },
        )
      Nil
    }
    False -> Nil
  }
}
