import gluegun
import gluegun/connection
import gluegun/error
import gluegun/message
import gluegun/websocket
import startest
import startest/expect
import startest/test_tree

pub fn websocket_close_tests() -> test_tree.TestTree {
  startest.describe("public WebSocket teardown", [
    startest.it(
      "keeps errors typed and accepts an already-exited process",
      fn() { error_paths() |> expect.to_equal(Ok(Nil)) },
    ),
    startest.it("exchanges and releases using public socket APIs", fn() {
      with_server("normal", fn(port) {
        let assert Ok(socket) = connect(port, options(500))
        let assert Ok(connection) = owned_connection()
        websocket.send_text(socket, "hello") |> expect.to_equal(Ok(Nil))
        websocket.receive_app_frame(socket)
        |> expect.to_equal(Ok(message.Text("hello")))
        gluegun.websocket_close(socket) |> expect.to_equal(Ok(Nil))
        websocket.close(socket) |> expect.to_equal(Ok(Nil))
        assert_released(connection)
      })
      |> expect.to_equal(Ok(Nil))
    }),
    startest.it("keeps send_close_frame separate from teardown", fn() {
      with_server("stall", fn(port) {
        let assert Ok(socket) = connect(port, options(50))
        let assert Ok(connection) = owned_connection()
        websocket.send_close_frame(socket) |> expect.to_equal(Ok(Nil))
        // A live connection remains discoverable after the frame-only call.
        owned_connection() |> expect.to_equal(Ok(connection))
        websocket.close(socket) |> expect.to_equal(Error(error.Timeout))
        assert_released(connection)
      })
      |> expect.to_equal(Ok(Nil))
    }),
    startest.it("handles a peer close already received by the caller", fn() {
      with_server("peer_close", fn(port) {
        let assert Ok(socket) = connect(port, options(500))
        let assert Ok(connection) = owned_connection()
        websocket.receive_frame(socket) |> expect.to_equal(Ok(message.Close))
        websocket.close(socket) |> expect.to_equal(Ok(Nil))
        assert_released(connection)
      })
      |> expect.to_equal(Ok(Nil))
    }),
    startest.it("reports peer failure and still releases the process", fn() {
      with_server("failure", fn(port) {
        let assert Ok(socket) = connect(port, options(500))
        let assert Ok(connection) = owned_connection()
        case websocket.close(socket) {
          Error(error.ConnectionDown(_)) -> Nil
          other ->
            other |> expect.to_equal(Error(error.ConnectionDown("closed")))
        }
        assert_released(connection)
      })
      |> expect.to_equal(Ok(Nil))
    }),
    startest.it("remembers a received peer close with a reason", fn() {
      with_server("peer_reason", fn(port) {
        let assert Ok(socket) = connect(port, options(500))
        let assert Ok(connection) = owned_connection()
        websocket.receive_app_frame(socket)
        |> expect.to_equal(Ok(message.CloseWithReason(1000, <<"bye":utf8>>)))
        websocket.close(socket) |> expect.to_equal(Ok(Nil))
        assert_released(connection)
      })
      |> expect.to_equal(Ok(Nil))
    }),
    startest.it("bounds an unresponsive peer", fn() {
      timeout_scenario("stall", options(50), 30, 500)
    }),
    startest.it("does not extend the deadline for incoming frames", fn() {
      timeout_scenario("chatter", options(50), 30, 500)
    }),
    startest.it("supports a zero close deadline", fn() {
      timeout_scenario("stall", options(0), 0, 500)
    }),
    startest.it("bounds cleanup even with an infinite receive timeout", fn() {
      timeout_scenario(
        "stall",
        websocket.options() |> websocket.with_timeout(connection.infinity()),
        4900,
        6500,
      )
    }),
    startest.it("does not mistake Gun's closing timeout for a peer reply", fn() {
      let upgrade =
        websocket.upgrade_options()
        |> websocket.with_closing_timeout(timeout(20))
      timeout_scenario(
        "stall",
        options(500) |> websocket.with_upgrade_options(upgrade),
        0,
        500,
      )
    }),
    startest.it("preserves callback errors after cleanup timeout", fn() {
      with_server("stall", fn(port) {
        let assert Ok(connection) = {
          websocket.with_socket(
            host: "127.0.0.1",
            port: port,
            path: "/echo",
            options: options(50),
            callback: fn(_) {
              let assert Ok(connection) = owned_connection()
              remember_connection(connection)
              Error(error.InvalidMessage("callback failed"))
            },
          )
          |> expect.to_equal(Error(error.InvalidMessage("callback failed")))
          remembered_connection()
        }
        assert_released(connection)
      })
      |> expect.to_equal(Ok(Nil))
    }),
    startest.it("allows a callback to close its own socket", fn() {
      with_server("normal", fn(port) {
        websocket.with_socket(
          host: "127.0.0.1",
          port: port,
          path: "/echo",
          options: options(500),
          callback: fn(socket) { websocket.close(socket) },
        )
      })
      |> expect.to_equal(Ok(Nil))
    }),
    startest.it("returns a cleanup error after callback success", fn() {
      with_server("stall", fn(port) {
        let result =
          websocket.with_socket(
            host: "127.0.0.1",
            port: port,
            path: "/echo",
            options: options(50),
            callback: fn(_) {
              let assert Ok(connection) = owned_connection()
              remember_connection(connection)
              Ok(Nil)
            },
          )
        result |> expect.to_equal(Error(error.Timeout))
        let assert Ok(connection) = remembered_connection()
        assert_released(connection)
      })
      |> expect.to_equal(Ok(Nil))
    }),
  ])
}

fn timeout_scenario(
  name: String,
  options: websocket.Options,
  minimum: Int,
  maximum: Int,
) -> Nil {
  with_server(name, fn(port) {
    // Upgrade must complete before a short or zero receive timeout is used.
    let assert Ok(socket) = case
      websocket.options_timeout(options) == timeout(0)
    {
      True -> connect_zero_timeout(port)
      False -> connect(port, options)
    }
    let assert Ok(connection) = owned_connection()
    let #(result, elapsed) = timed(fn() { websocket.close(socket) })
    result |> expect.to_equal(Error(error.Timeout))
    { elapsed >= minimum && elapsed < maximum } |> expect.to_equal(True)
    assert_released(connection)
  })
  |> expect.to_equal(Ok(Nil))
}

fn connect(
  port: Int,
  options: websocket.Options,
) -> Result(websocket.Socket, error.GluegunError) {
  websocket.connect(
    host: "127.0.0.1",
    port: port,
    path: "/echo",
    options: options,
  )
}

fn connect_zero_timeout(
  port: Int,
) -> Result(websocket.Socket, error.GluegunError) {
  let assert Ok(connection) =
    connection.options()
    |> connection.with_transport(connection.Tcp)
    |> connection.with_protocols([connection.Http1])
    |> connection.open(host: "127.0.0.1", port: port)
  let assert Ok(protocol) = connection.await_up(connection, timeout(500))
  let assert Ok(stream) =
    websocket.upgrade_with_protocol(connection, protocol, "/echo", [])
  let assert Ok(Nil) = websocket.await_upgrade(connection, stream, timeout(500))
  Ok(websocket.socket(connection, stream, timeout(0)))
}

fn options(milliseconds: Int) -> websocket.Options {
  websocket.options() |> websocket.with_timeout(timeout(milliseconds))
}

fn timeout(milliseconds: Int) -> connection.Timeout {
  let assert Ok(timeout) = connection.milliseconds(milliseconds)
  timeout
}

@external(erlang, "gluegun_ws_close_test", "with_server")
fn with_server(
  name: String,
  callback: fn(Int) -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ws_close_test", "owned_connection")
fn owned_connection() -> Result(connection.Connection, error.GluegunError)

@external(erlang, "gluegun_ws_close_test", "assert_released")
fn assert_released(
  connection: connection.Connection,
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ws_close_test", "timed")
fn timed(
  callback: fn() -> Result(Nil, error.GluegunError),
) -> #(Result(Nil, error.GluegunError), Int)

@external(erlang, "gluegun_ws_close_test", "remember_connection")
fn remember_connection(connection: connection.Connection) -> Nil

@external(erlang, "gluegun_ws_close_test", "remembered_connection")
fn remembered_connection() -> Result(connection.Connection, error.GluegunError)

@external(erlang, "gluegun_ws_close_test", "error_paths")
fn error_paths() -> Result(Nil, error.GluegunError)
