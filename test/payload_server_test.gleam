import gleam/http
import gleam/list
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/message
import gluegun/request
import gluegun/websocket

pub type Server

pub fn keeps_a_pending_http_request_usable_after_rejected_bodies_test() -> Nil {
  use server, port <- with_server(False)
  let conn = open(port)
  use <- with_connection(conn)
  let pending = post(conn, "/pending", <<0, 255, 128>>)
  let actual_1 = await_http(server)
  let expected_1 = Ok(#("/pending", <<0, 255, 128>>))
  let assert #(True, _, _) = #(actual_1 == expected_1, actual_1, expected_1)

  list.each([<<1:size(1)>>, <<255, 1:size(1)>>], fn(body) {
    let actual_2 =
      request.request(conn, http.Post, "/rejected", [], body, request.options())
    let expected_2 = Error(error.InvalidOptions("Payload(NonByteAligned)"))
    let assert #(True, _, _) = #(actual_2 == expected_2, actual_2, expected_2)
    Nil
  })

  release_pending(server)
  expect_response(conn, pending, <<0, 255, 128>>)
  let next = post(conn, "/next", <<0, 1, 127, 128, 255>>)
  let actual_3 = await_http(server)
  let expected_3 = Ok(#("/next", <<0, 1, 127, 128, 255>>))
  let assert #(True, _, _) = #(actual_3 == expected_3, actual_3, expected_3)
  expect_response(conn, next, <<0, 1, 127, 128, 255>>)

  let empty = post(conn, "/empty", <<>>)
  let actual_4 = await_http(server)
  let expected_4 = Ok(#("/empty", <<>>))
  let assert #(True, _, _) = #(actual_4 == expected_4, actual_4, expected_4)
  expect_response(conn, empty, <<>>)
  Nil
}

pub fn keeps_another_pending_response_usable_while_retrying_rejected_http_chunks_test() -> Nil {
  use server, port <- with_server(False)
  let conn = open(port)
  use <- with_connection(conn)
  let pending = post(conn, "/pending", <<42, 128, 255>>)
  let actual_5 = await_http(server)
  let expected_5 = Ok(#("/pending", <<42, 128, 255>>))
  let assert #(True, _, _) = #(actual_5 == expected_5, actual_5, expected_5)

  let assert Ok(stream) =
    request.start_stream(conn, http.Post, "/stream", [], request.options())
  let actual_6 = request.data(conn, stream, fin.NoFin, <<>>)
  let expected_6 = Ok(Nil)
  let assert #(True, _, _) = #(actual_6 == expected_6, actual_6, expected_6)
  let actual_7 = request.data(conn, stream, fin.NoFin, <<0, 255>>)
  let expected_7 = Ok(Nil)
  let assert #(True, _, _) = #(actual_7 == expected_7, actual_7, expected_7)

  list.each([fin.NoFin, fin.Fin], fn(end) {
    list.each([<<1:size(1)>>, <<128, 1:size(1)>>], fn(body) {
      let actual_8 = request.data(conn, stream, end, body)
      let expected_8 = Error(error.InvalidOptions("Payload(NonByteAligned)"))
      let assert #(True, _, _) = #(actual_8 == expected_8, actual_8, expected_8)
      Nil
    })
  })

  let actual_9 = request.data(conn, stream, fin.NoFin, <<128>>)
  let expected_9 = Ok(Nil)
  let assert #(True, _, _) = #(actual_9 == expected_9, actual_9, expected_9)
  let actual_10 = request.data(conn, stream, fin.Fin, <<1>>)
  let expected_10 = Ok(Nil)
  let assert #(True, _, _) = #(actual_10 == expected_10, actual_10, expected_10)

  release_pending(server)
  expect_response(conn, pending, <<42, 128, 255>>)
  let actual_11 = await_http(server)
  let expected_11 = Ok(#("/stream", <<0, 255, 128, 1>>))
  let assert #(True, _, _) = #(actual_11 == expected_11, actual_11, expected_11)
  expect_response(conn, stream, <<0, 255, 128, 1>>)

  let assert Ok(empty_stream) =
    request.start_stream(
      conn,
      http.Post,
      "/empty-stream",
      [],
      request.options(),
    )
  let actual_12 = request.data(conn, empty_stream, fin.Fin, <<>>)
  let expected_12 = Ok(Nil)
  let assert #(True, _, _) = #(actual_12 == expected_12, actual_12, expected_12)
  let actual_13 = await_http(server)
  let expected_13 = Ok(#("/empty-stream", <<>>))
  let assert #(True, _, _) = #(actual_13 == expected_13, actual_13, expected_13)
  expect_response(conn, empty_stream, <<>>)

  let next = post(conn, "/next", <<42, 255>>)
  let actual_14 = await_http(server)
  let expected_14 = Ok(#("/next", <<42, 255>>))
  let assert #(True, _, _) = #(actual_14 == expected_14, actual_14, expected_14)
  expect_response(conn, next, <<42, 255>>)
  Nil
}

pub fn rejects_websocket_frames_and_whole_batches_without_partial_writes_test() -> Nil {
  use server, port <- with_server(True)
  let conn = open(port)
  use <- with_connection(conn)
  let assert Ok(stream) =
    websocket.upgrade_with_protocol_and_options(
      conn,
      connection.Http1,
      "/ws",
      [],
      websocket.upgrade_options()
        |> websocket.with_silence_pings(False),
    )
  let actual_15 =
    websocket.await_upgrade(conn, stream, connection.default_timeout())
  let expected_15 = Ok(Nil)
  let assert #(True, _, _) = #(actual_15 == expected_15, actual_15, expected_15)

  list.each([<<1:size(1)>>, <<255, 1:size(1)>>], fn(body) {
    list.each(
      [
        message.Binary(body),
        message.Ping(body),
        message.Pong(body),
        message.CloseWithReason(1000, body),
      ],
      fn(frame) {
        let actual_16 = websocket.send(conn, stream, frame)
        let expected_16 =
          Error(error.InvalidMessage("InvalidFrame(NonByteAlignedPayload)"))
        let assert #(True, _, _) = #(
          actual_16 == expected_16,
          actual_16,
          expected_16,
        )
        let actual_17 =
          websocket.send_many(conn, stream, [
            message.Text("must not reach the server"),
            frame,
            message.Binary(<<99>>),
          ])
        let expected_17 =
          Error(error.InvalidMessage("InvalidFrame(NonByteAlignedPayload)"))
        let assert #(True, _, _) = #(
          actual_17 == expected_17,
          actual_17,
          expected_17,
        )

        // The next frame is an ordered wire barrier for both rejected sends.
        let marker = message.Binary(<<0, 128, 255>>)
        let actual_18 = websocket.send(conn, stream, marker)
        let expected_18 = Ok(Nil)
        let assert #(True, _, _) = #(
          actual_18 == expected_18,
          actual_18,
          expected_18,
        )
        let actual_19 = await_frame(server)
        let expected_19 = Ok(marker)
        let assert #(True, _, _) = #(
          actual_19 == expected_19,
          actual_19,
          expected_19,
        )
        let actual_20 =
          message.await(conn, stream, connection.default_timeout())
        let expected_20 = Ok(message.WebSocket(marker))
        let assert #(True, _, _) = #(
          actual_20 == expected_20,
          actual_20,
          expected_20,
        )
        Nil
      },
    )
  })

  list.each(
    [
      message.Binary(<<>>),
      message.Ping(<<0, 255>>),
      message.Pong(<<128, 255>>),
      message.Pong(<<>>),
    ],
    fn(frame) {
      let actual_21 = websocket.send(conn, stream, frame)
      let expected_21 = Ok(Nil)
      let assert #(True, _, _) = #(
        actual_21 == expected_21,
        actual_21,
        expected_21,
      )
      let actual_22 = await_frame(server)
      let expected_22 = Ok(frame)
      let assert #(True, _, _) = #(
        actual_22 == expected_22,
        actual_22,
        expected_22,
      )
      case frame {
        message.Binary(_) -> {
          let actual_23 =
            message.await(conn, stream, connection.default_timeout())
          let expected_23 = Ok(message.WebSocket(frame))
          let assert #(True, _, _) = #(
            actual_23 == expected_23,
            actual_23,
            expected_23,
          )
          Nil
        }
        message.Ping(body) -> {
          let actual_24 =
            message.await(conn, stream, connection.default_timeout())
          let expected_24 = Ok(message.WebSocket(message.Pong(body)))
          let assert #(True, _, _) = #(
            actual_24 == expected_24,
            actual_24,
            expected_24,
          )
          Nil
        }
        _ -> Nil
      }
    },
  )

  let actual_25 = websocket.send(conn, stream, message.Ping(<<>>))
  let expected_25 = Ok(Nil)
  let assert #(True, _, _) = #(actual_25 == expected_25, actual_25, expected_25)
  let actual_26 = await_frame(server)
  let expected_26 = Ok(message.Ping(<<>>))
  let assert #(True, _, _) = #(actual_26 == expected_26, actual_26, expected_26)

  let close = message.CloseWithReason(1000, <<"done":utf8>>)
  let actual_27 = websocket.send(conn, stream, close)
  let expected_27 = Ok(Nil)
  let assert #(True, _, _) = #(actual_27 == expected_27, actual_27, expected_27)
  let actual_28 = await_frame(server)
  let expected_28 = Ok(close)
  let assert #(True, _, _) = #(actual_28 == expected_28, actual_28, expected_28)
  Nil
}

fn open(port: Int) -> connection.Connection {
  let assert Ok(conn) =
    connection.options()
    |> connection.with_transport(connection.Tcp)
    |> connection.with_protocols([connection.Http1])
    |> connection.open(host: "127.0.0.1", port: port)
  conn
}

fn post(
  conn: connection.Connection,
  path: String,
  body: BitArray,
) -> request.Stream {
  let assert Ok(stream) =
    request.request(conn, http.Post, path, [], body, request.options())
  stream
}

fn expect_response(
  conn: connection.Connection,
  stream: request.Stream,
  body: BitArray,
) -> Nil {
  let assert Ok(message.Response(end, 200, _)) =
    message.await(conn, stream, connection.default_timeout())
  case end {
    fin.Fin -> {
      let actual_29 = body
      let expected_29 = <<>>
      let assert #(True, _, _) = #(
        actual_29 == expected_29,
        actual_29,
        expected_29,
      )
      Nil
    }
    fin.NoFin -> {
      let actual_30 =
        message.await_body(conn, stream, connection.default_timeout())
      let expected_30 = Ok(body)
      let assert #(True, _, _) = #(
        actual_30 == expected_30,
        actual_30,
        expected_30,
      )
      Nil
    }
  }
}

@external(erlang, "gluegun_payload_server_test", "with_server")
fn with_server(websocket: Bool, callback: fn(Server, Int) -> Nil) -> Nil

@external(erlang, "gluegun_payload_server_test", "with_connection")
fn with_connection(conn: connection.Connection, callback: fn() -> Nil) -> Nil

@external(erlang, "gluegun_payload_server_test", "await_http")
fn await_http(server: Server) -> Result(#(String, BitArray), String)

@external(erlang, "gluegun_payload_server_test", "release_pending")
fn release_pending(server: Server) -> Nil

@external(erlang, "gluegun_payload_server_test", "await_frame")
fn await_frame(server: Server) -> Result(message.Frame, String)
