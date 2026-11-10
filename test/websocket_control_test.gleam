import gleam/bit_array
import gleam/list
import gleam/string
import gluegun/connection
import gluegun/error
import gluegun/message
import gluegun/request
import gluegun/websocket

pub fn accepts_empty_and_exact_limit_control_payloads_test() -> Nil {
  list.each([0, 125], fn(size) {
    list.each([message.Ping(bytes(size)), message.Pong(bytes(size))], fn(frame) {
      let assert Ok(value) = capture_frame(frame)
      value
    })
  })
  list.each([0, 123], fn(size) {
    let assert Ok(value) =
      capture_frame(message.CloseWithReason(1000, bytes(size)))
    value
  })
  let assert Ok(_) = capture_frame(message.Close)
  Nil
}

pub fn accepts_registered_and_application_close_code_ranges_test() -> Nil {
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
      let assert Ok(value) = capture_frame(message.CloseWithReason(code, <<>>))
      value
    },
  )
  Nil
}

pub fn rejects_invalid_controls_without_casting_a_frame_list_test() -> Nil {
  list.each(invalid_frames(), fn(entry) {
    let #(frame, expected_error) = entry
    let actual_1 =
      websocket.send_frame(
        websocket.socket(current_connection(), stream_ref(), timeout()),
        frame,
      )
    let expected_1 = Error(expected_error)
    let assert #(True, _, _) = #(actual_1 == expected_1, actual_1, expected_1)
    let actual_2 = capture_frames()
    let expected_2 = Error(Nil)
    let assert #(True, _, _) = #(actual_2 == expected_2, actual_2, expected_2)

    list.each(
      [
        [message.Text("prefix"), frame],
        [frame, message.Text("suffix")],
        [message.Text("prefix"), frame, message.Text("suffix")],
      ],
      fn(frames) {
        let actual_3 =
          websocket.send_many(
            websocket.socket(current_connection(), stream_ref(), timeout()),
            frames,
          )
        let expected_3 = Error(expected_error)
        let assert #(True, _, _) = #(
          actual_3 == expected_3,
          actual_3,
          expected_3,
        )
        let actual_4 = capture_frames()
        let expected_4 = Error(Nil)
        let assert #(True, _, _) = #(
          actual_4 == expected_4,
          actual_4,
          expected_4,
        )
        Nil
      },
    )
  })
  Nil
}

pub fn counts_close_reason_bytes_rather_than_characters_test() -> Nil {
  let reason = string.repeat("é", 61) <> "a"
  let assert Ok(_) =
    capture_frame(message.CloseWithReason(1000, bit_array.from_string(reason)))
  let actual_5 =
    websocket.send_frame(
      websocket.socket(current_connection(), stream_ref(), timeout()),
      message.CloseWithReason(
        1000,
        bit_array.from_string(string.repeat("é", 62)),
      ),
    )
  let expected_5 =
    Error(error.InvalidMessage("InvalidFrame(Close(PayloadTooLarge(124, 123)))"))
  let assert #(True, _, _) = #(actual_5 == expected_5, actual_5, expected_5)
  let actual_6 = capture_frames()
  let expected_6 = Error(Nil)
  let assert #(True, _, _) = #(actual_6 == expected_6, actual_6, expected_6)
  Nil
}

pub fn exchanges_exact_limit_ping_and_pong_frames_with_a_local_server_test() -> Nil {
  with_echo_connection(fn(conn, stream) {
    list.each([1, 125], fn(size) {
      let payload = bytes(size)
      let actual_7 =
        websocket.send_frame(
          websocket.socket(conn, stream, timeout()),
          message.Ping(payload),
        )
      let expected_7 = Ok(Nil)
      let assert #(True, _, _) = #(actual_7 == expected_7, actual_7, expected_7)
      let actual_8 =
        websocket.receive_frame(websocket.socket(conn, stream, timeout()))
      let expected_8 = Ok(message.Pong(payload))
      let assert #(True, _, _) = #(actual_8 == expected_8, actual_8, expected_8)

      let actual_9 =
        websocket.send_many(websocket.socket(conn, stream, timeout()), [
          message.Pong(payload),
        ])
      let expected_9 = Ok(Nil)
      let assert #(True, _, _) = #(actual_9 == expected_9, actual_9, expected_9)
      let actual_10 =
        websocket.receive_frame(websocket.socket(conn, stream, timeout()))
      let expected_10 = Ok(message.Pong(payload))
      let assert #(True, _, _) = #(
        actual_10 == expected_10,
        actual_10,
        expected_10,
      )
      Nil
    })
  })
  Nil
}

pub fn exchanges_an_exact_limit_close_reason_with_a_local_server_test() -> Nil {
  with_echo_connection(fn(conn, stream) {
    let frame =
      message.CloseWithReason(
        1000,
        bit_array.from_string(string.repeat("é", 61) <> "a"),
      )
    let actual_11 =
      websocket.send_frame(websocket.socket(conn, stream, timeout()), frame)
    let expected_11 = Ok(Nil)
    let assert #(True, _, _) = #(
      actual_11 == expected_11,
      actual_11,
      expected_11,
    )
    let actual_12 =
      websocket.receive_frame(websocket.socket(conn, stream, timeout()))
    let expected_12 = Ok(frame)
    let assert #(True, _, _) = #(
      actual_12 == expected_12,
      actual_12,
      expected_12,
    )
    Nil
  })
  with_echo_connection(fn(conn, stream) {
    let frame = message.CloseWithReason(1000, bytes(123))
    let actual_13 =
      websocket.send_many(websocket.socket(conn, stream, timeout()), [frame])
    let expected_13 = Ok(Nil)
    let assert #(True, _, _) = #(
      actual_13 == expected_13,
      actual_13,
      expected_13,
    )
    let actual_14 =
      websocket.receive_frame(websocket.socket(conn, stream, timeout()))
    let expected_14 = Ok(frame)
    let assert #(True, _, _) = #(
      actual_14 == expected_14,
      actual_14,
      expected_14,
    )
    Nil
  })
  Nil
}

pub fn keeps_a_live_connection_usable_after_each_rejected_send_test() -> Nil {
  with_echo_connection(fn(conn, stream) {
    list.each(invalid_frames(), fn(entry) {
      let #(frame, expected_error) = entry
      let actual_15 =
        websocket.send_frame(websocket.socket(conn, stream, timeout()), frame)
      let expected_15 = Error(expected_error)
      let assert #(True, _, _) = #(
        actual_15 == expected_15,
        actual_15,
        expected_15,
      )
      exchange_marker(conn, stream)

      let actual_16 =
        websocket.send_many(websocket.socket(conn, stream, timeout()), [
          message.Text("must not be sent"),
          frame,
        ])
      let expected_16 = Error(expected_error)
      let assert #(True, _, _) = #(
        actual_16 == expected_16,
        actual_16,
        expected_16,
      )
      exchange_marker(conn, stream)
    })
  })
  Nil
}

pub fn validates_socket_ping_and_pong_helpers_test() -> Nil {
  with_echo_connection(fn(conn, stream) {
    let socket = websocket.socket(conn, stream, timeout())
    let actual_17 = websocket.ping(socket, bytes(126))
    let expected_17 =
      Error(error.InvalidMessage(
        "InvalidFrame(Ping(PayloadTooLarge(126, 125)))",
      ))
    let assert #(True, _, _) = #(
      actual_17 == expected_17,
      actual_17,
      expected_17,
    )
    let actual_18 = websocket.pong(socket, bytes(126))
    let expected_18 =
      Error(error.InvalidMessage(
        "InvalidFrame(Pong(PayloadTooLarge(126, 125)))",
      ))
    let assert #(True, _, _) = #(
      actual_18 == expected_18,
      actual_18,
      expected_18,
    )
    exchange_marker(conn, stream)
  })
  Nil
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
  let actual_19 =
    websocket.send_frame(
      websocket.socket(conn, stream, timeout()),
      message.Text("still usable"),
    )
  let expected_19 = Ok(Nil)
  let assert #(True, _, _) = #(actual_19 == expected_19, actual_19, expected_19)
  let actual_20 =
    websocket.receive_frame(websocket.socket(conn, stream, timeout()))
  let expected_20 = Ok(message.Text("still usable"))
  let assert #(True, _, _) = #(actual_20 == expected_20, actual_20, expected_20)
  Nil
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
