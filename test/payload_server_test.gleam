import gleam/list
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/message
import gluegun/request
import gluegun/websocket
import startest
import startest/expect
import startest/test_tree

pub type Server

pub fn payload_server_tests() -> test_tree.TestTree {
  startest.describe("payload guards on local Gun connections", [
    startest.it(
      "keeps a pending HTTP request usable after rejected bodies",
      fn() {
        use server, port <- with_server(False)
        let conn = open(port)
        use <- with_connection(conn)
        let pending = post(conn, "/pending", <<0, 255, 128>>)
        await_http(server)
        |> expect.to_equal(Ok(#("/pending", <<0, 255, 128>>)))

        list.each([<<1:size(1)>>, <<255, 1:size(1)>>], fn(body) {
          request.request(
            conn,
            request.Post,
            "/rejected",
            [],
            body,
            request.options(),
          )
          |> expect.to_equal(
            Error(error.InvalidOptions("Payload(NonByteAligned)")),
          )
        })

        release_pending(server)
        expect_response(conn, pending, <<0, 255, 128>>)
        let next = post(conn, "/next", <<0, 1, 127, 128, 255>>)
        await_http(server)
        |> expect.to_equal(Ok(#("/next", <<0, 1, 127, 128, 255>>)))
        expect_response(conn, next, <<0, 1, 127, 128, 255>>)

        let empty = post(conn, "/empty", <<>>)
        await_http(server) |> expect.to_equal(Ok(#("/empty", <<>>)))
        expect_response(conn, empty, <<>>)
      },
    ),
    startest.it(
      "keeps another pending response usable while retrying rejected HTTP chunks",
      fn() {
        use server, port <- with_server(False)
        let conn = open(port)
        use <- with_connection(conn)
        let pending = post(conn, "/pending", <<42, 128, 255>>)
        await_http(server)
        |> expect.to_equal(Ok(#("/pending", <<42, 128, 255>>)))

        let assert Ok(stream) =
          request.start_stream(
            conn,
            request.Post,
            "/stream",
            [],
            request.options(),
          )
        request.data(conn, stream, fin.NoFin, <<>>)
        |> expect.to_equal(Ok(Nil))
        request.data(conn, stream, fin.NoFin, <<0, 255>>)
        |> expect.to_equal(Ok(Nil))

        list.each([fin.NoFin, fin.Fin], fn(end) {
          list.each([<<1:size(1)>>, <<128, 1:size(1)>>], fn(body) {
            request.data(conn, stream, end, body)
            |> expect.to_equal(
              Error(error.InvalidOptions("Payload(NonByteAligned)")),
            )
          })
        })

        request.data(conn, stream, fin.NoFin, <<128>>)
        |> expect.to_equal(Ok(Nil))
        request.data(conn, stream, fin.Fin, <<1>>)
        |> expect.to_equal(Ok(Nil))

        release_pending(server)
        expect_response(conn, pending, <<42, 128, 255>>)
        await_http(server)
        |> expect.to_equal(Ok(#("/stream", <<0, 255, 128, 1>>)))
        expect_response(conn, stream, <<0, 255, 128, 1>>)

        let assert Ok(empty_stream) =
          request.start_stream(
            conn,
            request.Post,
            "/empty-stream",
            [],
            request.options(),
          )
        request.data(conn, empty_stream, fin.Fin, <<>>)
        |> expect.to_equal(Ok(Nil))
        await_http(server) |> expect.to_equal(Ok(#("/empty-stream", <<>>)))
        expect_response(conn, empty_stream, <<>>)

        let next = post(conn, "/next", <<42, 255>>)
        await_http(server) |> expect.to_equal(Ok(#("/next", <<42, 255>>)))
        expect_response(conn, next, <<42, 255>>)
      },
    ),
    startest.it(
      "rejects WebSocket frames and whole batches without partial writes",
      fn() {
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
        websocket.await_upgrade(conn, stream, connection.default_timeout())
        |> expect.to_equal(Ok(Nil))

        list.each([<<1:size(1)>>, <<255, 1:size(1)>>], fn(body) {
          list.each(
            [
              message.Binary(body),
              message.Ping(body),
              message.Pong(body),
              message.CloseWithReason(1000, body),
            ],
            fn(frame) {
              websocket.send(conn, stream, frame)
              |> expect.to_equal(
                Error(error.InvalidMessage(
                  "InvalidFrame(NonByteAlignedPayload)",
                )),
              )
              websocket.send_many(conn, stream, [
                message.Text("must not reach the server"),
                frame,
                message.Binary(<<99>>),
              ])
              |> expect.to_equal(
                Error(error.InvalidMessage(
                  "InvalidFrame(NonByteAlignedPayload)",
                )),
              )

              // The next frame is an ordered wire barrier for both rejected sends.
              let marker = message.Binary(<<0, 128, 255>>)
              websocket.send(conn, stream, marker)
              |> expect.to_equal(Ok(Nil))
              await_frame(server) |> expect.to_equal(Ok(marker))
              message.await(conn, stream, connection.default_timeout())
              |> expect.to_equal(Ok(message.WebSocket(marker)))
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
            websocket.send(conn, stream, frame) |> expect.to_equal(Ok(Nil))
            await_frame(server) |> expect.to_equal(Ok(frame))
            case frame {
              message.Binary(_) ->
                message.await(conn, stream, connection.default_timeout())
                |> expect.to_equal(Ok(message.WebSocket(frame)))
              message.Ping(body) ->
                message.await(conn, stream, connection.default_timeout())
                |> expect.to_equal(Ok(message.WebSocket(message.Pong(body))))
              _ -> Nil
            }
          },
        )

        websocket.send(conn, stream, message.Ping(<<>>))
        |> expect.to_equal(Ok(Nil))
        await_frame(server) |> expect.to_equal(Ok(message.Ping(<<>>)))

        let close = message.CloseWithReason(1000, <<"done":utf8>>)
        websocket.send(conn, stream, close) |> expect.to_equal(Ok(Nil))
        await_frame(server) |> expect.to_equal(Ok(close))
      },
    ),
  ])
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
    request.request(conn, request.Post, path, [], body, request.options())
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
    fin.Fin -> body |> expect.to_equal(<<>>)
    fin.NoFin ->
      message.await_body(conn, stream, connection.default_timeout())
      |> expect.to_equal(Ok(body))
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
