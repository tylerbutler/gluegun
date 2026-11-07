import gleam/bit_array
import gleam/list
import gleam/string
import gluegun/connection
import gluegun/error
import gluegun/message
import gluegun/request
import gluegun/websocket
import startest
import startest/expect
import startest/test_tree

pub fn websocket_control_tests() -> test_tree.TestTree {
  startest.describe("WebSocket control-frame validation", [
    startest.it("accepts empty and exact-limit control payloads", fn() {
      list.each([0, 125], fn(size) {
        list.each(
          [message.Ping(bytes(size)), message.Pong(bytes(size))],
          fn(frame) {
            capture_frame(frame)
            |> expect.to_be_ok()
          },
        )
      })
      list.each([0, 123], fn(size) {
        capture_frame(message.CloseWithReason(1000, bytes(size)))
        |> expect.to_be_ok()
      })
      capture_frame(message.Close) |> expect.to_be_ok()
      Nil
    }),
    startest.it("accepts registered and application close code ranges", fn() {
      list.each(
        [
          1000,
          1001,
          1002,
          1003,
          1007,
          1008,
          1009,
          1010,
          1011,
          1012,
          1013,
          1014,
          3000,
          3999,
          4000,
          4999,
        ],
        fn(code) {
          capture_frame(message.CloseWithReason(code, <<>>))
          |> expect.to_be_ok()
        },
      )
    }),
    startest.it("rejects invalid controls without casting a frame list", fn() {
      list.each(invalid_frames(), fn(entry) {
        let #(frame, expected_error) = entry
        websocket.send(current_connection(), stream_ref(), frame)
        |> expect.to_equal(Error(expected_error))
        capture_frames() |> expect.to_equal(Error(Nil))

        list.each(
          [
            [message.Text("prefix"), frame],
            [frame, message.Text("suffix")],
            [message.Text("prefix"), frame, message.Text("suffix")],
          ],
          fn(frames) {
            websocket.send_many(current_connection(), stream_ref(), frames)
            |> expect.to_equal(Error(expected_error))
            capture_frames() |> expect.to_equal(Error(Nil))
          },
        )
      })
    }),
    startest.it("counts close-reason bytes rather than characters", fn() {
      let reason = string.repeat("é", 61) <> "a"
      capture_frame(message.CloseWithReason(1000, bit_array.from_string(reason)))
      |> expect.to_be_ok()
      websocket.send(
        current_connection(),
        stream_ref(),
        message.CloseWithReason(
          1000,
          bit_array.from_string(string.repeat("é", 62)),
        ),
      )
      |> expect.to_equal(
        Error(error.InvalidMessage(
          "InvalidFrame(Close(PayloadTooLarge(124, 123)))",
        )),
      )
      capture_frames() |> expect.to_equal(Error(Nil))
    }),
    startest.it(
      "exchanges exact-limit Ping and Pong frames with a local server",
      fn() {
        with_echo_connection(fn(conn, stream) {
          list.each([1, 125], fn(size) {
            let payload = bytes(size)
            websocket.send(conn, stream, message.Ping(payload))
            |> expect.to_equal(Ok(Nil))
            websocket.receive(conn, stream, timeout())
            |> expect.to_equal(Ok(message.Pong(payload)))

            websocket.send_many(conn, stream, [message.Pong(payload)])
            |> expect.to_equal(Ok(Nil))
            websocket.receive(conn, stream, timeout())
            |> expect.to_equal(Ok(message.Pong(payload)))
          })
        })
      },
    ),
    startest.it(
      "exchanges an exact-limit close reason with a local server",
      fn() {
        with_echo_connection(fn(conn, stream) {
          let frame =
            message.CloseWithReason(
              1000,
              bit_array.from_string(string.repeat("é", 61) <> "a"),
            )
          websocket.send(conn, stream, frame)
          |> expect.to_equal(Ok(Nil))
          websocket.receive(conn, stream, timeout())
          |> expect.to_equal(Ok(frame))
        })
        with_echo_connection(fn(conn, stream) {
          let frame = message.CloseWithReason(1000, bytes(123))
          websocket.send_many(conn, stream, [frame])
          |> expect.to_equal(Ok(Nil))
          websocket.receive(conn, stream, timeout())
          |> expect.to_equal(Ok(frame))
        })
      },
    ),
    startest.it("keeps a live connection usable after each rejected send", fn() {
      with_echo_connection(fn(conn, stream) {
        list.each(invalid_frames(), fn(entry) {
          let #(frame, expected_error) = entry
          websocket.send(conn, stream, frame)
          |> expect.to_equal(Error(expected_error))
          exchange_marker(conn, stream)

          websocket.send_many(conn, stream, [
            message.Text("must not be sent"),
            frame,
          ])
          |> expect.to_equal(Error(expected_error))
          exchange_marker(conn, stream)
        })
      })
    }),
    startest.it("validates socket Ping and Pong helpers", fn() {
      with_echo_connection(fn(conn, stream) {
        let socket = websocket.socket(conn, stream, timeout())
        websocket.ping(socket, bytes(126))
        |> expect.to_equal(
          Error(error.InvalidMessage(
            "InvalidFrame(Ping(PayloadTooLarge(126, 125)))",
          )),
        )
        websocket.pong(socket, bytes(126))
        |> expect.to_equal(
          Error(error.InvalidMessage(
            "InvalidFrame(Pong(PayloadTooLarge(126, 125)))",
          )),
        )
        exchange_marker(conn, stream)
      })
    }),
  ])
}

fn bytes(size: Int) -> BitArray {
  bit_array.from_string(string.repeat("a", size))
}

fn invalid_frames() -> List(#(message.Frame, error.GluegunError)) {
  [
    #(
      message.Ping(bytes(126)),
      error.InvalidMessage("InvalidFrame(Ping(PayloadTooLarge(126, 125)))"),
    ),
    #(
      message.Pong(bytes(126)),
      error.InvalidMessage("InvalidFrame(Pong(PayloadTooLarge(126, 125)))"),
    ),
    #(
      message.CloseWithReason(1000, bytes(124)),
      error.InvalidMessage("InvalidFrame(Close(PayloadTooLarge(124, 123)))"),
    ),
    #(
      message.CloseWithReason(1000, <<255>>),
      error.InvalidMessage("InvalidFrame(Close(InvalidUtf8))"),
    ),
    #(
      message.CloseWithReason(1000, <<0xC3>>),
      error.InvalidMessage("InvalidFrame(Close(InvalidUtf8))"),
    ),
    #(
      message.CloseWithReason(1000, <<0xC0, 0xAF>>),
      error.InvalidMessage("InvalidFrame(Close(InvalidUtf8))"),
    ),
  ]
  |> list.append(
    list.map(
      [-1, 0, 999, 1004, 1005, 1006, 1015, 1016, 2999, 5000, 65_536],
      fn(code) {
        #(
          message.CloseWithReason(code, <<>>),
          error.InvalidMessage(
            "InvalidFrame(Close(InvalidCode(" <> string.inspect(code) <> ")))",
          ),
        )
      },
    ),
  )
}

fn timeout() -> connection.Timeout {
  let assert Ok(timeout) = connection.milliseconds(5000)
  timeout
}

fn exchange_marker(conn: connection.Connection, stream: request.Stream) -> Nil {
  websocket.send(conn, stream, message.Text("still usable"))
  |> expect.to_equal(Ok(Nil))
  websocket.receive(conn, stream, timeout())
  |> expect.to_equal(Ok(message.Text("still usable")))
}

@external(erlang, "gluegun_ws_test", "capture_ws_send_frame")
fn capture_frame(
  frame: message.Frame,
) -> Result(message.GunMessage, error.GluegunError)

@external(erlang, "gluegun_ws_test", "capture_ws_send_frames")
fn capture_frames() -> Result(List(#(String, BitArray)), Nil)

@external(erlang, "gluegun_ffi_test", "current_connection")
fn current_connection() -> connection.Connection

@external(erlang, "gluegun_ffi_test", "stream_ref")
fn stream_ref() -> request.Stream

@external(erlang, "gluegun_ws_control_test", "with_echo_connection")
fn with_echo_connection(
  callback: fn(connection.Connection, request.Stream) -> Nil,
) -> Nil
