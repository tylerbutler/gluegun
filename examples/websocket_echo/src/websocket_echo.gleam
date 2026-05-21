/// WebSocket echo example using gluegun's high-level Socket API.
///
/// Connects to a local echo server at ws://localhost:8080/echo, sends one
/// text frame, receives the echoed reply, then sends a close frame.
///
/// ## Protocol note
///
/// This example uses HTTP/1.1. Gun does NOT support WebSocket over HTTP/2
/// (RFC 8441). `websocket.options()` defaults WebSocket connections to
/// HTTP/1.1, and low-level `websocket.upgrade_with_protocol` rejects HTTP/2
/// before calling Gun.
///
/// Once the connection is upgraded to WebSocket it is exclusively used for
/// WebSocket frames; you cannot send concurrent HTTP requests on it.
import gleam/int
import gleam/io
import gluegun/error
import gluegun/message
import gluegun/websocket

const host = "localhost"

const port = 8080

const path = "/echo"

pub fn main() {
  let assert Ok(socket) =
    websocket.connect(
      host: host,
      port: port,
      path: path,
      options: websocket.options(),
    )

  io.println("WebSocket connected!")

  let assert Ok(Nil) = websocket.send_text(socket, "hello")

  case websocket.receive_app_frame(socket) {
    Ok(message.Text(reply)) -> io.println("Received: " <> reply)
    Ok(other) -> io.println("Unexpected frame: " <> frame_to_string(other))
    Error(err) -> io.println("Error: " <> error_to_string(err))
  }

  let assert Ok(Nil) = websocket.send_close_frame(socket)
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
  }
}
