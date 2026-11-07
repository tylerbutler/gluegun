import gleam/list
import gleam/string
import gluegun/client
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/internal
import gluegun/message
import gluegun/request
import gluegun/websocket
import startest
import startest/expect
import startest/test_tree

pub fn payload_tests() -> test_tree.TestTree {
  startest.describe("byte-aligned outbound payloads", [
    startest.describe(
      "HTTP bodies",
      list.map(valid_payloads(), fn(payload) {
        startest.it("preserves request data " <> string.inspect(payload), fn() {
          let assert Ok(_) =
            request.request(
              current_connection(),
              request.Post,
              "/upload",
              [],
              payload,
              request.options(),
            )
          capture_request_body() |> expect.to_equal(Ok(payload))
        })
      }),
    ),
    startest.describe(
      "HTTP chunks",
      list.flat_map(valid_payloads(), fn(payload) {
        list.map([fin.NoFin, fin.Fin], fn(final) {
          startest.it(
            "preserves chunk "
              <> string.inspect(payload)
              <> " "
              <> string.inspect(final),
            fn() {
              request.data(current_connection(), stream_ref(), final, payload)
              |> expect.to_equal(Ok(Nil))
              case payload, final {
                <<>>, fin.NoFin -> has_payload_cast() |> expect.to_be_false
                _, _ -> capture_data_payload() |> expect.to_equal(Ok(payload))
              }
            },
          )
        })
      }),
    ),
    startest.describe(
      "HTTP rejection",
      list.map(invalid_payloads(), fn(payload) {
        startest.it("rejects HTTP payload " <> string.inspect(payload), fn() {
          request.request(
            current_connection(),
            request.Post,
            "/upload",
            [],
            payload,
            request.options(),
          )
          |> expect.to_equal(
            Error(error.InvalidOptions("Payload(NonByteAligned)")),
          )

          list.each([fin.NoFin, fin.Fin], fn(final) {
            request.data(current_connection(), stream_ref(), final, payload)
            |> expect.to_equal(
              Error(error.InvalidOptions("Payload(NonByteAligned)")),
            )
          })
          has_payload_cast() |> expect.to_be_false
        })
      }),
    ),
    startest.it("client helpers reject trailing bits before collecting", fn() {
      list.each([client.post, client.put, client.patch], fn(send) {
        send(current_connection(), "/", [], <<1:size(1)>>, timeout())
        |> expect.to_equal(
          Error(error.InvalidOptions("Payload(NonByteAligned)")),
        )
      })
      client.new(request.Post, "/")
      |> client.with_body(body: <<255, 1:size(1)>>)
      |> client.send(connection: current_connection())
      |> expect.to_equal(Error(error.InvalidOptions("Payload(NonByteAligned)")))
      has_payload_cast() |> expect.to_be_false
    }),
    startest.describe(
      "WebSocket bytes",
      list.flat_map(valid_payloads(), fn(payload) {
        list.map(byte_frames(payload), fn(frame) {
          startest.it("preserves frame " <> string.inspect(frame), fn() {
            let assert Ok(raw_frame) = capture_ws_send_frame(frame)
            safe_decode_message(raw_frame)
            |> expect.to_equal(Ok(message.WebSocket(frame)))
          })
        })
      }),
    ),
    startest.describe(
      "WebSocket rejection",
      list.flat_map(invalid_payloads(), fn(payload) {
        list.map(byte_frames(payload), fn(frame) {
          startest.it("rejects frame and batch " <> string.inspect(frame), fn() {
            websocket.send(current_connection(), stream_ref(), frame)
            |> expect.to_equal(invalid_frame_error())
            list.each(
              [
                [frame, message.Text("valid")],
                [message.Text("valid"), frame, message.Binary(<<>>)],
                [message.Text("valid"), frame],
              ],
              fn(frames) {
                websocket.send_many(current_connection(), stream_ref(), frames)
                |> expect.to_equal(invalid_frame_error())
              },
            )
            has_payload_cast() |> expect.to_be_false
          })
        })
      }),
    ),
    startest.it("socket helpers share byte validation", fn() {
      let socket =
        websocket.socket(current_connection(), stream_ref(), timeout())
      list.each(
        [websocket.send_binary, websocket.ping, websocket.pong],
        fn(send) {
          send(socket, <<1:size(1)>>) |> expect.to_equal(invalid_frame_error())
        },
      )
      websocket.send_frame(socket, message.CloseWithReason(1000, <<1:size(1)>>))
      |> expect.to_equal(invalid_frame_error())
      has_payload_cast() |> expect.to_be_false
    }),
  ])
}

fn valid_payloads() -> List(BitArray) {
  [<<>>, <<0>>, <<0, 1, 127>>]
}

fn invalid_payloads() -> List(BitArray) {
  [<<1:size(1)>>, <<127:size(7)>>, <<255, 1:size(1)>>, <<255, 127:size(7)>>]
}

fn byte_frames(payload: BitArray) -> List(message.Frame) {
  [
    message.Binary(payload),
    message.Ping(payload),
    message.Pong(payload),
    message.CloseWithReason(1000, payload),
  ]
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
