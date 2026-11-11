import gleam/http
import gleam/list
import gluegun/client
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/internal
import gluegun/message
import gluegun/request
import gluegun/websocket

pub fn http_bodies_preserves_request_data_empty_test() -> Nil {
  let payload = <<>>
  let assert Ok(_) =
    request.request(
      current_connection(),
      http.Post,
      "/upload",
      [],
      payload,
      request.options(),
    )
  let actual_1 = capture_request_body()
  let expected_1 = Ok(payload)
  let assert #(True, _, _) = #(actual_1 == expected_1, actual_1, expected_1)
  Nil
}

pub fn http_bodies_preserves_request_data_zero_byte_test() -> Nil {
  let payload = <<0>>
  let assert Ok(_) =
    request.request(
      current_connection(),
      http.Post,
      "/upload",
      [],
      payload,
      request.options(),
    )
  let actual_2 = capture_request_body()
  let expected_2 = Ok(payload)
  let assert #(True, _, _) = #(actual_2 == expected_2, actual_2, expected_2)
  Nil
}

pub fn http_bodies_preserves_request_data_three_bytes_test() -> Nil {
  let payload = <<0, 1, 127>>
  let assert Ok(_) =
    request.request(
      current_connection(),
      http.Post,
      "/upload",
      [],
      payload,
      request.options(),
    )
  let actual_3 = capture_request_body()
  let expected_3 = Ok(payload)
  let assert #(True, _, _) = #(actual_3 == expected_3, actual_3, expected_3)
  Nil
}

pub fn http_chunks_preserves_chunk_empty_no_fin_test() -> Nil {
  let payload = <<>>
  let final = fin.NoFin
  let actual_4 =
    request.data(current_connection(), stream_ref(), final, payload)
  let expected_4 = Ok(Nil)
  let assert #(True, _, _) = #(actual_4 == expected_4, actual_4, expected_4)
  let actual_5 = has_payload_cast()
  let expected_5 = False
  let assert #(True, _, _) = #(actual_5 == expected_5, actual_5, expected_5)
  Nil
}

pub fn http_chunks_preserves_chunk_empty_fin_test() -> Nil {
  let payload = <<>>
  let final = fin.Fin
  let actual_6 =
    request.data(current_connection(), stream_ref(), final, payload)
  let expected_6 = Ok(Nil)
  let assert #(True, _, _) = #(actual_6 == expected_6, actual_6, expected_6)
  let actual_7 = capture_data_payload()
  let expected_7 = Ok(payload)
  let assert #(True, _, _) = #(actual_7 == expected_7, actual_7, expected_7)
  Nil
}

pub fn http_chunks_preserves_chunk_zero_byte_no_fin_test() -> Nil {
  let payload = <<0>>
  let final = fin.NoFin
  let actual_8 =
    request.data(current_connection(), stream_ref(), final, payload)
  let expected_8 = Ok(Nil)
  let assert #(True, _, _) = #(actual_8 == expected_8, actual_8, expected_8)
  let actual_9 = capture_data_payload()
  let expected_9 = Ok(payload)
  let assert #(True, _, _) = #(actual_9 == expected_9, actual_9, expected_9)
  Nil
}

pub fn http_chunks_preserves_chunk_zero_byte_fin_test() -> Nil {
  let payload = <<0>>
  let final = fin.Fin
  let actual_10 =
    request.data(current_connection(), stream_ref(), final, payload)
  let expected_10 = Ok(Nil)
  let assert #(True, _, _) = #(actual_10 == expected_10, actual_10, expected_10)
  let actual_11 = capture_data_payload()
  let expected_11 = Ok(payload)
  let assert #(True, _, _) = #(actual_11 == expected_11, actual_11, expected_11)
  Nil
}

pub fn http_chunks_preserves_chunk_three_bytes_no_fin_test() -> Nil {
  let payload = <<0, 1, 127>>
  let final = fin.NoFin
  let actual_12 =
    request.data(current_connection(), stream_ref(), final, payload)
  let expected_12 = Ok(Nil)
  let assert #(True, _, _) = #(actual_12 == expected_12, actual_12, expected_12)
  let actual_13 = capture_data_payload()
  let expected_13 = Ok(payload)
  let assert #(True, _, _) = #(actual_13 == expected_13, actual_13, expected_13)
  Nil
}

pub fn http_chunks_preserves_chunk_three_bytes_fin_test() -> Nil {
  let payload = <<0, 1, 127>>
  let final = fin.Fin
  let actual_14 =
    request.data(current_connection(), stream_ref(), final, payload)
  let expected_14 = Ok(Nil)
  let assert #(True, _, _) = #(actual_14 == expected_14, actual_14, expected_14)
  let actual_15 = capture_data_payload()
  let expected_15 = Ok(payload)
  let assert #(True, _, _) = #(actual_15 == expected_15, actual_15, expected_15)
  Nil
}

pub fn http_rejection_rejects_http_payload_one_bit_test() -> Nil {
  let payload = <<1:size(1)>>
  let actual_16 =
    request.request(
      current_connection(),
      http.Post,
      "/upload",
      [],
      payload,
      request.options(),
    )
  let expected_16 = Error(error.InvalidOptions("Payload(NonByteAligned)"))
  let assert #(True, _, _) = #(actual_16 == expected_16, actual_16, expected_16)

  list.each([fin.NoFin, fin.Fin], fn(final) {
    let actual_17 =
      request.data(current_connection(), stream_ref(), final, payload)
    let expected_17 = Error(error.InvalidOptions("Payload(NonByteAligned)"))
    let assert #(True, _, _) = #(
      actual_17 == expected_17,
      actual_17,
      expected_17,
    )
    Nil
  })
  let actual_18 = has_payload_cast()
  let expected_18 = False
  let assert #(True, _, _) = #(actual_18 == expected_18, actual_18, expected_18)
  Nil
}

pub fn http_rejection_rejects_http_payload_seven_bits_test() -> Nil {
  let payload = <<127:size(7)>>
  let actual_19 =
    request.request(
      current_connection(),
      http.Post,
      "/upload",
      [],
      payload,
      request.options(),
    )
  let expected_19 = Error(error.InvalidOptions("Payload(NonByteAligned)"))
  let assert #(True, _, _) = #(actual_19 == expected_19, actual_19, expected_19)

  list.each([fin.NoFin, fin.Fin], fn(final) {
    let actual_20 =
      request.data(current_connection(), stream_ref(), final, payload)
    let expected_20 = Error(error.InvalidOptions("Payload(NonByteAligned)"))
    let assert #(True, _, _) = #(
      actual_20 == expected_20,
      actual_20,
      expected_20,
    )
    Nil
  })
  let actual_21 = has_payload_cast()
  let expected_21 = False
  let assert #(True, _, _) = #(actual_21 == expected_21, actual_21, expected_21)
  Nil
}

pub fn http_rejection_rejects_http_payload_byte_and_one_bit_test() -> Nil {
  let payload = <<255, 1:size(1)>>
  let actual_22 =
    request.request(
      current_connection(),
      http.Post,
      "/upload",
      [],
      payload,
      request.options(),
    )
  let expected_22 = Error(error.InvalidOptions("Payload(NonByteAligned)"))
  let assert #(True, _, _) = #(actual_22 == expected_22, actual_22, expected_22)

  list.each([fin.NoFin, fin.Fin], fn(final) {
    let actual_23 =
      request.data(current_connection(), stream_ref(), final, payload)
    let expected_23 = Error(error.InvalidOptions("Payload(NonByteAligned)"))
    let assert #(True, _, _) = #(
      actual_23 == expected_23,
      actual_23,
      expected_23,
    )
    Nil
  })
  let actual_24 = has_payload_cast()
  let expected_24 = False
  let assert #(True, _, _) = #(actual_24 == expected_24, actual_24, expected_24)
  Nil
}

pub fn http_rejection_rejects_http_payload_byte_and_seven_bits_test() -> Nil {
  let payload = <<255, 127:size(7)>>
  let actual_25 =
    request.request(
      current_connection(),
      http.Post,
      "/upload",
      [],
      payload,
      request.options(),
    )
  let expected_25 = Error(error.InvalidOptions("Payload(NonByteAligned)"))
  let assert #(True, _, _) = #(actual_25 == expected_25, actual_25, expected_25)

  list.each([fin.NoFin, fin.Fin], fn(final) {
    let actual_26 =
      request.data(current_connection(), stream_ref(), final, payload)
    let expected_26 = Error(error.InvalidOptions("Payload(NonByteAligned)"))
    let assert #(True, _, _) = #(
      actual_26 == expected_26,
      actual_26,
      expected_26,
    )
    Nil
  })
  let actual_27 = has_payload_cast()
  let expected_27 = False
  let assert #(True, _, _) = #(actual_27 == expected_27, actual_27, expected_27)
  Nil
}

pub fn client_helpers_reject_trailing_bits_before_collecting_test() -> Nil {
  list.each([client.post, client.put, client.patch], fn(send) {
    let actual_28 =
      send(current_connection(), "/", [], <<1:size(1)>>, timeout())
    let expected_28 = Error(error.InvalidOptions("Payload(NonByteAligned)"))
    let assert #(True, _, _) = #(
      actual_28 == expected_28,
      actual_28,
      expected_28,
    )
    Nil
  })
  let actual_29 = {
    client.new(http.Post, "/")
    |> client.with_body(body: <<255, 1:size(1)>>)
    |> client.send(connection: current_connection())
  }
  let expected_29 = Error(error.InvalidOptions("Payload(NonByteAligned)"))
  let assert #(True, _, _) = #(actual_29 == expected_29, actual_29, expected_29)
  let actual_30 = has_payload_cast()
  let expected_30 = False
  let assert #(True, _, _) = #(actual_30 == expected_30, actual_30, expected_30)
  Nil
}

pub fn websocket_bytes_preserves_frame_empty_binary_test() -> Nil {
  let payload = <<>>
  let frame = message.Binary(payload)
  let assert Ok(raw_frame) = capture_ws_send_frame(frame)
  let actual_31 = safe_decode_message(raw_frame)
  let expected_31 = Ok(message.WebSocket(frame))
  let assert #(True, _, _) = #(actual_31 == expected_31, actual_31, expected_31)
  Nil
}

pub fn websocket_bytes_preserves_frame_empty_ping_test() -> Nil {
  let payload = <<>>
  let frame = message.Ping(payload)
  let assert Ok(raw_frame) = capture_ws_send_frame(frame)
  let actual_32 = safe_decode_message(raw_frame)
  let expected_32 = Ok(message.WebSocket(frame))
  let assert #(True, _, _) = #(actual_32 == expected_32, actual_32, expected_32)
  Nil
}

pub fn websocket_bytes_preserves_frame_empty_pong_test() -> Nil {
  let payload = <<>>
  let frame = message.Pong(payload)
  let assert Ok(raw_frame) = capture_ws_send_frame(frame)
  let actual_33 = safe_decode_message(raw_frame)
  let expected_33 = Ok(message.WebSocket(frame))
  let assert #(True, _, _) = #(actual_33 == expected_33, actual_33, expected_33)
  Nil
}

pub fn websocket_bytes_preserves_frame_empty_close_with_reason_test() -> Nil {
  let payload = <<>>
  let frame = message.CloseWithReason(1000, payload)
  let assert Ok(raw_frame) = capture_ws_send_frame(frame)
  let actual_34 = safe_decode_message(raw_frame)
  let expected_34 = Ok(message.WebSocket(frame))
  let assert #(True, _, _) = #(actual_34 == expected_34, actual_34, expected_34)
  Nil
}

pub fn websocket_bytes_preserves_frame_zero_byte_binary_test() -> Nil {
  let payload = <<0>>
  let frame = message.Binary(payload)
  let assert Ok(raw_frame) = capture_ws_send_frame(frame)
  let actual_35 = safe_decode_message(raw_frame)
  let expected_35 = Ok(message.WebSocket(frame))
  let assert #(True, _, _) = #(actual_35 == expected_35, actual_35, expected_35)
  Nil
}

pub fn websocket_bytes_preserves_frame_zero_byte_ping_test() -> Nil {
  let payload = <<0>>
  let frame = message.Ping(payload)
  let assert Ok(raw_frame) = capture_ws_send_frame(frame)
  let actual_36 = safe_decode_message(raw_frame)
  let expected_36 = Ok(message.WebSocket(frame))
  let assert #(True, _, _) = #(actual_36 == expected_36, actual_36, expected_36)
  Nil
}

pub fn websocket_bytes_preserves_frame_zero_byte_pong_test() -> Nil {
  let payload = <<0>>
  let frame = message.Pong(payload)
  let assert Ok(raw_frame) = capture_ws_send_frame(frame)
  let actual_37 = safe_decode_message(raw_frame)
  let expected_37 = Ok(message.WebSocket(frame))
  let assert #(True, _, _) = #(actual_37 == expected_37, actual_37, expected_37)
  Nil
}

pub fn websocket_bytes_preserves_frame_zero_byte_close_with_reason_test() -> Nil {
  let payload = <<0>>
  let frame = message.CloseWithReason(1000, payload)
  let assert Ok(raw_frame) = capture_ws_send_frame(frame)
  let actual_38 = safe_decode_message(raw_frame)
  let expected_38 = Ok(message.WebSocket(frame))
  let assert #(True, _, _) = #(actual_38 == expected_38, actual_38, expected_38)
  Nil
}

pub fn websocket_bytes_preserves_frame_three_bytes_binary_test() -> Nil {
  let payload = <<0, 1, 127>>
  let frame = message.Binary(payload)
  let assert Ok(raw_frame) = capture_ws_send_frame(frame)
  let actual_39 = safe_decode_message(raw_frame)
  let expected_39 = Ok(message.WebSocket(frame))
  let assert #(True, _, _) = #(actual_39 == expected_39, actual_39, expected_39)
  Nil
}

pub fn websocket_bytes_preserves_frame_three_bytes_ping_test() -> Nil {
  let payload = <<0, 1, 127>>
  let frame = message.Ping(payload)
  let assert Ok(raw_frame) = capture_ws_send_frame(frame)
  let actual_40 = safe_decode_message(raw_frame)
  let expected_40 = Ok(message.WebSocket(frame))
  let assert #(True, _, _) = #(actual_40 == expected_40, actual_40, expected_40)
  Nil
}

pub fn websocket_bytes_preserves_frame_three_bytes_pong_test() -> Nil {
  let payload = <<0, 1, 127>>
  let frame = message.Pong(payload)
  let assert Ok(raw_frame) = capture_ws_send_frame(frame)
  let actual_41 = safe_decode_message(raw_frame)
  let expected_41 = Ok(message.WebSocket(frame))
  let assert #(True, _, _) = #(actual_41 == expected_41, actual_41, expected_41)
  Nil
}

pub fn websocket_bytes_preserves_frame_three_bytes_close_with_reason_test() -> Nil {
  let payload = <<0, 1, 127>>
  let frame = message.CloseWithReason(1000, payload)
  let assert Ok(raw_frame) = capture_ws_send_frame(frame)
  let actual_42 = safe_decode_message(raw_frame)
  let expected_42 = Ok(message.WebSocket(frame))
  let assert #(True, _, _) = #(actual_42 == expected_42, actual_42, expected_42)
  Nil
}

pub fn websocket_rejection_rejects_frame_and_batch_one_bit_binary_test() -> Nil {
  let payload = <<1:size(1)>>
  let frame = message.Binary(payload)
  let actual_43 = websocket.send(current_connection(), stream_ref(), frame)
  let expected_43 = invalid_frame_error()
  let assert #(True, _, _) = #(actual_43 == expected_43, actual_43, expected_43)
  list.each(
    [
      [frame, message.Text("valid")],
      [message.Text("valid"), frame, message.Binary(<<>>)],
      [message.Text("valid"), frame],
    ],
    fn(frames) {
      let actual_44 =
        websocket.send_many(current_connection(), stream_ref(), frames)
      let expected_44 = invalid_frame_error()
      let assert #(True, _, _) = #(
        actual_44 == expected_44,
        actual_44,
        expected_44,
      )
      Nil
    },
  )
  let actual_45 = has_payload_cast()
  let expected_45 = False
  let assert #(True, _, _) = #(actual_45 == expected_45, actual_45, expected_45)
  Nil
}

pub fn websocket_rejection_rejects_frame_and_batch_one_bit_ping_test() -> Nil {
  let payload = <<1:size(1)>>
  let frame = message.Ping(payload)
  let actual_46 = websocket.send(current_connection(), stream_ref(), frame)
  let expected_46 = invalid_frame_error()
  let assert #(True, _, _) = #(actual_46 == expected_46, actual_46, expected_46)
  list.each(
    [
      [frame, message.Text("valid")],
      [message.Text("valid"), frame, message.Binary(<<>>)],
      [message.Text("valid"), frame],
    ],
    fn(frames) {
      let actual_47 =
        websocket.send_many(current_connection(), stream_ref(), frames)
      let expected_47 = invalid_frame_error()
      let assert #(True, _, _) = #(
        actual_47 == expected_47,
        actual_47,
        expected_47,
      )
      Nil
    },
  )
  let actual_48 = has_payload_cast()
  let expected_48 = False
  let assert #(True, _, _) = #(actual_48 == expected_48, actual_48, expected_48)
  Nil
}

pub fn websocket_rejection_rejects_frame_and_batch_one_bit_pong_test() -> Nil {
  let payload = <<1:size(1)>>
  let frame = message.Pong(payload)
  let actual_49 = websocket.send(current_connection(), stream_ref(), frame)
  let expected_49 = invalid_frame_error()
  let assert #(True, _, _) = #(actual_49 == expected_49, actual_49, expected_49)
  list.each(
    [
      [frame, message.Text("valid")],
      [message.Text("valid"), frame, message.Binary(<<>>)],
      [message.Text("valid"), frame],
    ],
    fn(frames) {
      let actual_50 =
        websocket.send_many(current_connection(), stream_ref(), frames)
      let expected_50 = invalid_frame_error()
      let assert #(True, _, _) = #(
        actual_50 == expected_50,
        actual_50,
        expected_50,
      )
      Nil
    },
  )
  let actual_51 = has_payload_cast()
  let expected_51 = False
  let assert #(True, _, _) = #(actual_51 == expected_51, actual_51, expected_51)
  Nil
}

pub fn websocket_rejection_rejects_frame_and_batch_one_bit_close_with_reason_test() -> Nil {
  let payload = <<1:size(1)>>
  let frame = message.CloseWithReason(1000, payload)
  let actual_52 = websocket.send(current_connection(), stream_ref(), frame)
  let expected_52 = invalid_frame_error()
  let assert #(True, _, _) = #(actual_52 == expected_52, actual_52, expected_52)
  list.each(
    [
      [frame, message.Text("valid")],
      [message.Text("valid"), frame, message.Binary(<<>>)],
      [message.Text("valid"), frame],
    ],
    fn(frames) {
      let actual_53 =
        websocket.send_many(current_connection(), stream_ref(), frames)
      let expected_53 = invalid_frame_error()
      let assert #(True, _, _) = #(
        actual_53 == expected_53,
        actual_53,
        expected_53,
      )
      Nil
    },
  )
  let actual_54 = has_payload_cast()
  let expected_54 = False
  let assert #(True, _, _) = #(actual_54 == expected_54, actual_54, expected_54)
  Nil
}

pub fn websocket_rejection_rejects_frame_and_batch_seven_bits_binary_test() -> Nil {
  let payload = <<127:size(7)>>
  let frame = message.Binary(payload)
  let actual_55 = websocket.send(current_connection(), stream_ref(), frame)
  let expected_55 = invalid_frame_error()
  let assert #(True, _, _) = #(actual_55 == expected_55, actual_55, expected_55)
  list.each(
    [
      [frame, message.Text("valid")],
      [message.Text("valid"), frame, message.Binary(<<>>)],
      [message.Text("valid"), frame],
    ],
    fn(frames) {
      let actual_56 =
        websocket.send_many(current_connection(), stream_ref(), frames)
      let expected_56 = invalid_frame_error()
      let assert #(True, _, _) = #(
        actual_56 == expected_56,
        actual_56,
        expected_56,
      )
      Nil
    },
  )
  let actual_57 = has_payload_cast()
  let expected_57 = False
  let assert #(True, _, _) = #(actual_57 == expected_57, actual_57, expected_57)
  Nil
}

pub fn websocket_rejection_rejects_frame_and_batch_seven_bits_ping_test() -> Nil {
  let payload = <<127:size(7)>>
  let frame = message.Ping(payload)
  let actual_58 = websocket.send(current_connection(), stream_ref(), frame)
  let expected_58 = invalid_frame_error()
  let assert #(True, _, _) = #(actual_58 == expected_58, actual_58, expected_58)
  list.each(
    [
      [frame, message.Text("valid")],
      [message.Text("valid"), frame, message.Binary(<<>>)],
      [message.Text("valid"), frame],
    ],
    fn(frames) {
      let actual_59 =
        websocket.send_many(current_connection(), stream_ref(), frames)
      let expected_59 = invalid_frame_error()
      let assert #(True, _, _) = #(
        actual_59 == expected_59,
        actual_59,
        expected_59,
      )
      Nil
    },
  )
  let actual_60 = has_payload_cast()
  let expected_60 = False
  let assert #(True, _, _) = #(actual_60 == expected_60, actual_60, expected_60)
  Nil
}

pub fn websocket_rejection_rejects_frame_and_batch_seven_bits_pong_test() -> Nil {
  let payload = <<127:size(7)>>
  let frame = message.Pong(payload)
  let actual_61 = websocket.send(current_connection(), stream_ref(), frame)
  let expected_61 = invalid_frame_error()
  let assert #(True, _, _) = #(actual_61 == expected_61, actual_61, expected_61)
  list.each(
    [
      [frame, message.Text("valid")],
      [message.Text("valid"), frame, message.Binary(<<>>)],
      [message.Text("valid"), frame],
    ],
    fn(frames) {
      let actual_62 =
        websocket.send_many(current_connection(), stream_ref(), frames)
      let expected_62 = invalid_frame_error()
      let assert #(True, _, _) = #(
        actual_62 == expected_62,
        actual_62,
        expected_62,
      )
      Nil
    },
  )
  let actual_63 = has_payload_cast()
  let expected_63 = False
  let assert #(True, _, _) = #(actual_63 == expected_63, actual_63, expected_63)
  Nil
}

pub fn websocket_rejection_rejects_frame_and_batch_seven_bits_close_with_reason_test() -> Nil {
  let payload = <<127:size(7)>>
  let frame = message.CloseWithReason(1000, payload)
  let actual_64 = websocket.send(current_connection(), stream_ref(), frame)
  let expected_64 = invalid_frame_error()
  let assert #(True, _, _) = #(actual_64 == expected_64, actual_64, expected_64)
  list.each(
    [
      [frame, message.Text("valid")],
      [message.Text("valid"), frame, message.Binary(<<>>)],
      [message.Text("valid"), frame],
    ],
    fn(frames) {
      let actual_65 =
        websocket.send_many(current_connection(), stream_ref(), frames)
      let expected_65 = invalid_frame_error()
      let assert #(True, _, _) = #(
        actual_65 == expected_65,
        actual_65,
        expected_65,
      )
      Nil
    },
  )
  let actual_66 = has_payload_cast()
  let expected_66 = False
  let assert #(True, _, _) = #(actual_66 == expected_66, actual_66, expected_66)
  Nil
}

pub fn websocket_rejection_rejects_frame_and_batch_byte_and_one_bit_binary_test() -> Nil {
  let payload = <<255, 1:size(1)>>
  let frame = message.Binary(payload)
  let actual_67 = websocket.send(current_connection(), stream_ref(), frame)
  let expected_67 = invalid_frame_error()
  let assert #(True, _, _) = #(actual_67 == expected_67, actual_67, expected_67)
  list.each(
    [
      [frame, message.Text("valid")],
      [message.Text("valid"), frame, message.Binary(<<>>)],
      [message.Text("valid"), frame],
    ],
    fn(frames) {
      let actual_68 =
        websocket.send_many(current_connection(), stream_ref(), frames)
      let expected_68 = invalid_frame_error()
      let assert #(True, _, _) = #(
        actual_68 == expected_68,
        actual_68,
        expected_68,
      )
      Nil
    },
  )
  let actual_69 = has_payload_cast()
  let expected_69 = False
  let assert #(True, _, _) = #(actual_69 == expected_69, actual_69, expected_69)
  Nil
}

pub fn websocket_rejection_rejects_frame_and_batch_byte_and_one_bit_ping_test() -> Nil {
  let payload = <<255, 1:size(1)>>
  let frame = message.Ping(payload)
  let actual_70 = websocket.send(current_connection(), stream_ref(), frame)
  let expected_70 = invalid_frame_error()
  let assert #(True, _, _) = #(actual_70 == expected_70, actual_70, expected_70)
  list.each(
    [
      [frame, message.Text("valid")],
      [message.Text("valid"), frame, message.Binary(<<>>)],
      [message.Text("valid"), frame],
    ],
    fn(frames) {
      let actual_71 =
        websocket.send_many(current_connection(), stream_ref(), frames)
      let expected_71 = invalid_frame_error()
      let assert #(True, _, _) = #(
        actual_71 == expected_71,
        actual_71,
        expected_71,
      )
      Nil
    },
  )
  let actual_72 = has_payload_cast()
  let expected_72 = False
  let assert #(True, _, _) = #(actual_72 == expected_72, actual_72, expected_72)
  Nil
}

pub fn websocket_rejection_rejects_frame_and_batch_byte_and_one_bit_pong_test() -> Nil {
  let payload = <<255, 1:size(1)>>
  let frame = message.Pong(payload)
  let actual_73 = websocket.send(current_connection(), stream_ref(), frame)
  let expected_73 = invalid_frame_error()
  let assert #(True, _, _) = #(actual_73 == expected_73, actual_73, expected_73)
  list.each(
    [
      [frame, message.Text("valid")],
      [message.Text("valid"), frame, message.Binary(<<>>)],
      [message.Text("valid"), frame],
    ],
    fn(frames) {
      let actual_74 =
        websocket.send_many(current_connection(), stream_ref(), frames)
      let expected_74 = invalid_frame_error()
      let assert #(True, _, _) = #(
        actual_74 == expected_74,
        actual_74,
        expected_74,
      )
      Nil
    },
  )
  let actual_75 = has_payload_cast()
  let expected_75 = False
  let assert #(True, _, _) = #(actual_75 == expected_75, actual_75, expected_75)
  Nil
}

pub fn websocket_rejection_rejects_frame_and_batch_byte_and_one_bit_close_with_reason_test() -> Nil {
  let payload = <<255, 1:size(1)>>
  let frame = message.CloseWithReason(1000, payload)
  let actual_76 = websocket.send(current_connection(), stream_ref(), frame)
  let expected_76 = invalid_frame_error()
  let assert #(True, _, _) = #(actual_76 == expected_76, actual_76, expected_76)
  list.each(
    [
      [frame, message.Text("valid")],
      [message.Text("valid"), frame, message.Binary(<<>>)],
      [message.Text("valid"), frame],
    ],
    fn(frames) {
      let actual_77 =
        websocket.send_many(current_connection(), stream_ref(), frames)
      let expected_77 = invalid_frame_error()
      let assert #(True, _, _) = #(
        actual_77 == expected_77,
        actual_77,
        expected_77,
      )
      Nil
    },
  )
  let actual_78 = has_payload_cast()
  let expected_78 = False
  let assert #(True, _, _) = #(actual_78 == expected_78, actual_78, expected_78)
  Nil
}

pub fn websocket_rejection_rejects_frame_and_batch_byte_and_seven_bits_binary_test() -> Nil {
  let payload = <<255, 127:size(7)>>
  let frame = message.Binary(payload)
  let actual_79 = websocket.send(current_connection(), stream_ref(), frame)
  let expected_79 = invalid_frame_error()
  let assert #(True, _, _) = #(actual_79 == expected_79, actual_79, expected_79)
  list.each(
    [
      [frame, message.Text("valid")],
      [message.Text("valid"), frame, message.Binary(<<>>)],
      [message.Text("valid"), frame],
    ],
    fn(frames) {
      let actual_80 =
        websocket.send_many(current_connection(), stream_ref(), frames)
      let expected_80 = invalid_frame_error()
      let assert #(True, _, _) = #(
        actual_80 == expected_80,
        actual_80,
        expected_80,
      )
      Nil
    },
  )
  let actual_81 = has_payload_cast()
  let expected_81 = False
  let assert #(True, _, _) = #(actual_81 == expected_81, actual_81, expected_81)
  Nil
}

pub fn websocket_rejection_rejects_frame_and_batch_byte_and_seven_bits_ping_test() -> Nil {
  let payload = <<255, 127:size(7)>>
  let frame = message.Ping(payload)
  let actual_82 = websocket.send(current_connection(), stream_ref(), frame)
  let expected_82 = invalid_frame_error()
  let assert #(True, _, _) = #(actual_82 == expected_82, actual_82, expected_82)
  list.each(
    [
      [frame, message.Text("valid")],
      [message.Text("valid"), frame, message.Binary(<<>>)],
      [message.Text("valid"), frame],
    ],
    fn(frames) {
      let actual_83 =
        websocket.send_many(current_connection(), stream_ref(), frames)
      let expected_83 = invalid_frame_error()
      let assert #(True, _, _) = #(
        actual_83 == expected_83,
        actual_83,
        expected_83,
      )
      Nil
    },
  )
  let actual_84 = has_payload_cast()
  let expected_84 = False
  let assert #(True, _, _) = #(actual_84 == expected_84, actual_84, expected_84)
  Nil
}

pub fn websocket_rejection_rejects_frame_and_batch_byte_and_seven_bits_pong_test() -> Nil {
  let payload = <<255, 127:size(7)>>
  let frame = message.Pong(payload)
  let actual_85 = websocket.send(current_connection(), stream_ref(), frame)
  let expected_85 = invalid_frame_error()
  let assert #(True, _, _) = #(actual_85 == expected_85, actual_85, expected_85)
  list.each(
    [
      [frame, message.Text("valid")],
      [message.Text("valid"), frame, message.Binary(<<>>)],
      [message.Text("valid"), frame],
    ],
    fn(frames) {
      let actual_86 =
        websocket.send_many(current_connection(), stream_ref(), frames)
      let expected_86 = invalid_frame_error()
      let assert #(True, _, _) = #(
        actual_86 == expected_86,
        actual_86,
        expected_86,
      )
      Nil
    },
  )
  let actual_87 = has_payload_cast()
  let expected_87 = False
  let assert #(True, _, _) = #(actual_87 == expected_87, actual_87, expected_87)
  Nil
}

pub fn websocket_rejection_rejects_frame_and_batch_byte_and_seven_bits_close_with_reason_test() -> Nil {
  let payload = <<255, 127:size(7)>>
  let frame = message.CloseWithReason(1000, payload)
  let actual_88 = websocket.send(current_connection(), stream_ref(), frame)
  let expected_88 = invalid_frame_error()
  let assert #(True, _, _) = #(actual_88 == expected_88, actual_88, expected_88)
  list.each(
    [
      [frame, message.Text("valid")],
      [message.Text("valid"), frame, message.Binary(<<>>)],
      [message.Text("valid"), frame],
    ],
    fn(frames) {
      let actual_89 =
        websocket.send_many(current_connection(), stream_ref(), frames)
      let expected_89 = invalid_frame_error()
      let assert #(True, _, _) = #(
        actual_89 == expected_89,
        actual_89,
        expected_89,
      )
      Nil
    },
  )
  let actual_90 = has_payload_cast()
  let expected_90 = False
  let assert #(True, _, _) = #(actual_90 == expected_90, actual_90, expected_90)
  Nil
}

pub fn socket_helpers_share_byte_validation_test() -> Nil {
  let socket = websocket.socket(current_connection(), stream_ref(), timeout())
  list.each([websocket.send_binary, websocket.ping, websocket.pong], fn(send) {
    let actual_91 = send(socket, <<1:size(1)>>)
    let expected_91 = invalid_frame_error()
    let assert #(True, _, _) = #(
      actual_91 == expected_91,
      actual_91,
      expected_91,
    )
    Nil
  })
  let actual_92 =
    websocket.send_frame(socket, message.CloseWithReason(1000, <<1:size(1)>>))
  let expected_92 = invalid_frame_error()
  let assert #(True, _, _) = #(actual_92 == expected_92, actual_92, expected_92)
  let actual_93 = has_payload_cast()
  let expected_93 = False
  let assert #(True, _, _) = #(actual_93 == expected_93, actual_93, expected_93)
  Nil
}

fn invalid_frame_error() -> Result(Nil, error.GluegunError) {
  Error(error.InvalidMessage("InvalidFrame(NonByteAlignedPayload)"))
}

fn timeout() -> connection.Timeout {
  let assert Ok(timeout) = connection.milliseconds(100)
  timeout
}

@external(erlang, "gluegun_ffi_test", "current_connection")
fn current_connection() -> internal.Connection

@external(erlang, "gluegun_ffi_test", "stream_ref")
fn stream_ref() -> internal.Stream

@external(erlang, "gluegun_payload_test", "capture_request_body")
fn capture_request_body() -> Result(BitArray, error.GluegunError)

@external(erlang, "gluegun_payload_test", "capture_data_payload")
fn capture_data_payload() -> Result(BitArray, error.GluegunError)

@external(erlang, "gluegun_payload_test", "has_payload_cast")
fn has_payload_cast() -> Bool

@external(erlang, "gluegun_ws_test", "capture_ws_send_frame")
fn capture_ws_send_frame(
  frame: message.Frame,
) -> Result(message.GunMessage, error.GluegunError)

@external(erlang, "gluegun_ffi", "safe_decode_message")
fn safe_decode_message(
  message: message.GunMessage,
) -> Result(message.Message, error.GluegunError)
