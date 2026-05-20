/// Scoped WebSocket chat example using gluegun's high-level Socket API.
///
/// Connects to a local server at ws://localhost:8080/chat, sends a text frame
/// and a binary frame, and prints one application-frame reply for each send.
import gleam/bit_array
import gleam/int
import gleam/io
import gleam/result
import gluegun/error
import gluegun/message
import gluegun/websocket

const host = "localhost"

const port = 8080

const path = "/chat"

pub fn main() {
  case
    websocket.with_socket(
      host: host,
      port: port,
      path: path,
      options: websocket.options(),
      callback: run_chat,
    )
  {
    Ok(Nil) -> io.println("chat finished")
    Error(err) -> io.println("chat failed: " <> error_to_string(err))
  }
}

fn run_chat(socket: websocket.Socket) -> Result(Nil, error.GluegunError) {
  use _ <- result.try(websocket.send_text(socket, "hello"))
  use text_reply <- result.try(websocket.receive_app_frame(socket))
  io.println("received: " <> frame_to_string(text_reply))

  use _ <- result.try(websocket.send_binary(socket, <<0x01, 0x02, 0x03>>))
  use binary_reply <- result.try(websocket.receive_app_frame(socket))
  io.println("received: " <> frame_to_string(binary_reply))

  Ok(Nil)
}

fn frame_to_string(frame: message.Frame) -> String {
  case frame {
    message.Text(text) -> "Text(" <> text <> ")"
    message.Binary(data) ->
      "Binary(" <> int.to_string(bit_array.byte_size(data)) <> " bytes)"
    message.Ping(data) ->
      "Ping(" <> int.to_string(bit_array.byte_size(data)) <> " bytes)"
    message.Pong(data) ->
      "Pong(" <> int.to_string(bit_array.byte_size(data)) <> " bytes)"
    message.Close -> "Close"
    message.CloseWithReason(code, reason) ->
      "CloseWithReason("
      <> int.to_string(code)
      <> ", "
      <> int.to_string(bit_array.byte_size(reason))
      <> " bytes)"
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
