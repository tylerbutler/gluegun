/// WebSocket echo example using gluegun.
///
/// Connects to a local echo server at ws://localhost:8080/echo, sends one
/// text frame, receives the echoed reply, then sends a close frame.
///
/// ## Protocol note
///
/// This example uses HTTP/1.1. Gun does NOT support WebSocket over HTTP/2
/// (RFC 8441). Use `websocket.upgrade_with_protocol` with the protocol from
/// `connection.await_up` so HTTP/2 is rejected before calling Gun.
///
/// Once the connection is upgraded to WebSocket it is exclusively used for
/// WebSocket frames; you cannot send concurrent HTTP requests on it.
import gleam/int
import gleam/io
import gluegun/connection.{Milliseconds}
import gluegun/message
import gluegun/websocket

const host = "localhost"

const port = 8080

const path = "/echo"

const timeout = Milliseconds(5000)

pub fn main() {
  // 1. Open a TCP connection to the server.
  let assert Ok(conn) =
    connection.options()
    |> connection.open(host: host, port: port)

  // 2. Wait until Gun confirms the connection is ready.
  let assert Ok(protocol) = connection.await_up(conn, timeout)

  // 3. Send the WebSocket upgrade request.
  //    Returns a stream reference used for all subsequent WebSocket I/O.
  let assert Ok(stream) =
    websocket.upgrade_with_protocol(conn, protocol, path, [])

  // 4. Wait for the server's 101 Switching Protocols confirmation.
  let assert Ok(Nil) = websocket.await_upgrade(conn, stream, timeout)

  io.println("WebSocket connected!")

  // 5. Send a text frame.
  let assert Ok(Nil) = websocket.send(conn, stream, message.Text("hello"))

  // 6. Receive the echoed reply.
  case websocket.receive(conn, stream, timeout) {
    Ok(message.Text(reply)) -> io.println("Received: " <> reply)
    Ok(other) -> io.println("Unexpected frame: " <> frame_to_string(other))
    Error(err) -> io.println("Error: " <> error_to_string(err))
  }

  // 7. Send a close frame to gracefully shut down the WebSocket stream.
  let assert Ok(Nil) = websocket.send(conn, stream, message.Close)

  // 8. Close the underlying Gun connection.
  let assert Ok(Nil) = connection.close(conn)
}

fn frame_to_string(frame: message.Frame) -> String {
  case frame {
    message.Text(s) -> "Text(" <> s <> ")"
    message.Binary(_) -> "Binary(<binary>)"
    message.Ping(_) -> "Ping"
    message.Pong(_) -> "Pong"
    message.Close -> "Close"
    message.CloseWithReason(code, _) ->
      "CloseWithReason(" <> int.to_string(code) <> ")"
  }
}

fn error_to_string(err) -> String {
  // In a real application use pattern matching on gluegun/error.GluegunError.
  let _ = err
  "(error)"
}
