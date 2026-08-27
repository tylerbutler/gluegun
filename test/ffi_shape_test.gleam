import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/internal
import gluegun/message
import gluegun/request
import startest
import startest/expect
import startest/test_tree

pub fn ffi_shape_tests() -> test_tree.TestTree {
  startest.describe("FFI shape decoding", [
    startest.describe("typed option conversion", [
      startest.it("converts timeouts", fn() {
        connection.options()
        |> connection.with_retry(connection.Milliseconds(123))
        |> connection.with_connect_timeout(connection.Infinity)
        |> connection.options_to_ffi
        |> gun_retry_and_connect_timeout
        |> expect.to_equal(#("123", "infinity"))
      }),
      startest.it("preserves protocol ordering", fn() {
        connection.options()
        |> connection.with_protocols([connection.Http2, connection.Http1])
        |> connection.options_to_ffi
        |> gun_protocols
        |> expect.to_equal(["http2", "http"])
      }),
    ]),
    startest.describe("message and error shapes", [
      startest.it("preserves invalid await_up protocol decode errors", fn() {
        gun_protocol_result("spdy")
        |> expect.to_equal(Error(error.DecodeError("Invalid protocol")))
      }),
      startest.it("maps timeout errors", fn() {
        gluegun_ffi_test_timeout_error()
        |> expect.to_equal(Error(error.Timeout))
      }),
      startest.it("decodes response message shapes", fn() {
        gluegun_ffi_test_response_message(fin.Fin, 200, [
          #("Content-Type", "text/plain"),
        ])
        |> message.decode
        |> expect.to_equal(
          Ok(message.Response(fin.Fin, 200, [#("content-type", "text/plain")])),
        )
      }),
      startest.it("decodes binary body data message shapes", fn() {
        gluegun_ffi_test_data_message(fin.NoFin, <<"hello":utf8>>)
        |> message.decode
        |> expect.to_equal(Ok(message.Data(fin.NoFin, <<"hello":utf8>>)))
      }),
      startest.it("keeps Gun stream references intact in push messages", fn() {
        let stream = gluegun_ffi_test_stream_ref()

        gluegun_ffi_test_push_message(stream, "GET", "/pushed", [])
        |> message.decode
        |> expect.to_equal(Ok(message.Push(stream, request.Get, "/pushed", [])))
      }),
      startest.it("decodes flow-control updates as Nil results", fn() {
        gluegun_ffi_test_capture_update_flow(1234)
        |> expect.to_equal(Ok(1234))
      }),
      startest.it(
        "decodes request errors instead of wrapping them as streams",
        fn() {
          gluegun_ffi_test_erlang_error()
          |> expect.to_equal(Error(error.ErlangError("Error(FunctionClause)")))
        },
      ),
      startest.it(
        "surfaces non-binary request fields as ErlangError instead of crashing",
        fn() {
          gluegun_ffi_test_invalid_binary_method()
          |> expect.to_equal(
            Error(error.ErlangError("Error(InvalidBinary(3.14))")),
          )
        },
      ),
      startest.it("keeps stream errors explicit", fn() {
        gluegun_ffi_test_stream_error()
        |> expect.to_equal(Error(error.StreamError("Boom")))
      }),
      startest.it("keeps close errors explicit", fn() {
        gluegun_ffi_test_invalid_connection()
        |> connection.close
        |> expect.to_equal(
          Error(error.ConnectionError("Error(SimpleOneForOne)")),
        )
      }),
      startest.it("keeps shutdown errors explicit", fn() {
        gluegun_ffi_test_invalid_connection()
        |> connection.shutdown
        |> expect.to_equal(
          Error(error.ConnectionError("Error(FunctionClause)")),
        )
      }),
      startest.it("rejects invalid UTF-8 websocket text", fn() {
        gluegun_ffi_test_invalid_utf8_websocket()
        |> expect.to_equal(Error(error.InvalidMessage("Ws(Text(InvalidUtf8))")))
      }),
    ]),
    startest.describe("Gun mailbox messages", [
      startest.it("decodes gun_inform mailbox tuples", fn() {
        mailbox_inform_message(103, [#("Link", "</style.css>")])
        |> message.decode
        |> expect.to_equal(Ok(message.Inform(103, [#("link", "</style.css>")])))
      }),
      startest.it("decodes gun_response mailbox tuples", fn() {
        mailbox_response_message(fin.NoFin, 200, [#("Server", "gun")])
        |> message.decode
        |> expect.to_equal(
          Ok(message.Response(fin.NoFin, 200, [#("server", "gun")])),
        )
      }),
      startest.it("decodes gun_data mailbox tuples", fn() {
        mailbox_data_message(fin.Fin, <<"hello":utf8>>)
        |> message.decode
        |> expect.to_equal(Ok(message.Data(fin.Fin, <<"hello":utf8>>)))
      }),
      startest.it("decodes gun_trailers mailbox tuples", fn() {
        mailbox_trailers_message([#("Expires", "soon")])
        |> message.decode
        |> expect.to_equal(Ok(message.Trailers([#("expires", "soon")])))
      }),
      startest.it("decodes gun_push mailbox tuples", fn() {
        let pushed = gluegun_ffi_test_stream_ref()

        mailbox_push_message(pushed, "GET", "/assets/app.css", [
          #("Accept", "text/css"),
        ])
        |> message.decode
        |> expect.to_equal(
          Ok(
            message.Push(pushed, request.Get, "/assets/app.css", [
              #("accept", "text/css"),
            ]),
          ),
        )
      }),
      startest.it("decodes gun_upgrade mailbox tuples", fn() {
        mailbox_upgrade_message(["websocket"], [#("Connection", "Upgrade")])
        |> message.decode
        |> expect.to_equal(
          Ok(message.Upgrade(["websocket"], [#("connection", "Upgrade")])),
        )
      }),
      startest.it("decodes gun_ws mailbox tuples", fn() {
        mailbox_websocket_frame_message(
          gluegun_ffi_test_text_frame(<<"hello":utf8>>),
        )
        |> message.decode
        |> expect.to_equal(Ok(message.WebSocket(message.Text("hello"))))
      }),
      startest.it("maps stream-level gun_error tuples", fn() {
        mailbox_stream_error_result()
        |> expect.to_equal(Error(error.StreamError("Boom")))
      }),
      startest.it("maps connection-level gun_error tuples", fn() {
        mailbox_connection_error_result()
        |> expect.to_equal(Error(error.ConnectionError("Boom")))
      }),
    ]),
    startest.describe("collected response bodies", [
      startest.it("returns the body when the last chunk carries Fin", fn() {
        await_body_with_fin(<<"hello":utf8>>)
        |> expect.to_equal(Ok(<<"hello":utf8>>))
      }),
      startest.it("returns the body when the response ends in trailers", fn() {
        await_body_with_trailers(<<"hello":utf8>>, [#("Expires", "soon")])
        |> expect.to_equal(Ok(<<"hello":utf8>>))
      }),
    ]),
  ])
}

fn gun_retry_and_connect_timeout(
  options: List(connection.ConnectOption),
) -> #(String, String) {
  #(gun_retry(options), gun_connect_timeout(options))
}

@external(erlang, "gluegun_ffi_test", "gun_protocols")
fn gun_protocols(options: List(connection.ConnectOption)) -> List(String)

@external(erlang, "gluegun_ffi_test", "gun_retry")
fn gun_retry(options: List(connection.ConnectOption)) -> String

@external(erlang, "gluegun_ffi_test", "gun_connect_timeout")
fn gun_connect_timeout(options: List(connection.ConnectOption)) -> String

@external(erlang, "gluegun_ffi_test", "protocol_result")
fn gun_protocol_result(
  protocol: String,
) -> Result(connection.Protocol, error.GluegunError)

@external(erlang, "gluegun_ffi_test", "response_message")
fn gluegun_ffi_test_response_message(
  fin: fin.Fin,
  status: Int,
  headers: List(#(String, String)),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "data_message")
fn gluegun_ffi_test_data_message(
  fin: fin.Fin,
  data: BitArray,
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "push_message")
fn gluegun_ffi_test_push_message(
  stream: internal.Stream,
  method: String,
  uri: String,
  headers: List(#(String, String)),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "stream_ref")
fn gluegun_ffi_test_stream_ref() -> internal.Stream

@external(erlang, "gluegun_ffi_test", "invalid_connection")
fn gluegun_ffi_test_invalid_connection() -> internal.Connection

@external(erlang, "gluegun_ffi_test", "erlang_error_result")
fn gluegun_ffi_test_erlang_error() -> Result(
  internal.Stream,
  error.GluegunError,
)

@external(erlang, "gluegun_ffi_test", "invalid_binary_method_result")
fn gluegun_ffi_test_invalid_binary_method() -> Result(
  internal.Stream,
  error.GluegunError,
)

@external(erlang, "gluegun_ffi_test", "stream_error_result")
fn gluegun_ffi_test_stream_error() -> Result(
  message.Message,
  error.GluegunError,
)

@external(erlang, "gluegun_ffi_test", "timeout_error_result")
fn gluegun_ffi_test_timeout_error() -> Result(
  message.Message,
  error.GluegunError,
)

@external(erlang, "gluegun_ffi_test", "invalid_utf8_websocket_result")
fn gluegun_ffi_test_invalid_utf8_websocket() -> Result(
  message.Message,
  error.GluegunError,
)

@external(erlang, "gluegun_ffi_test", "capture_update_flow")
fn gluegun_ffi_test_capture_update_flow(
  increment: Int,
) -> Result(Int, error.GluegunError)

/// A raw Gun WebSocket frame term, as carried inside a `gun_ws` message.
type GunFrame

@external(erlang, "gluegun_ffi_test", "text_frame")
fn gluegun_ffi_test_text_frame(data: BitArray) -> GunFrame

@external(erlang, "gluegun_ffi_test", "mailbox_inform_message")
fn mailbox_inform_message(
  status: Int,
  headers: List(#(String, String)),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "mailbox_response_message")
fn mailbox_response_message(
  fin: fin.Fin,
  status: Int,
  headers: List(#(String, String)),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "mailbox_data_message")
fn mailbox_data_message(fin: fin.Fin, data: BitArray) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "mailbox_trailers_message")
fn mailbox_trailers_message(
  headers: List(#(String, String)),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "mailbox_push_message")
fn mailbox_push_message(
  stream: internal.Stream,
  method: String,
  uri: String,
  headers: List(#(String, String)),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "mailbox_upgrade_message")
fn mailbox_upgrade_message(
  protocols: List(String),
  headers: List(#(String, String)),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "mailbox_websocket_frame_message")
fn mailbox_websocket_frame_message(frame: GunFrame) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "mailbox_stream_error_result")
fn mailbox_stream_error_result() -> Result(message.Message, error.GluegunError)

@external(erlang, "gluegun_ffi_test", "mailbox_connection_error_result")
fn mailbox_connection_error_result() -> Result(
  message.Message,
  error.GluegunError,
)

@external(erlang, "gluegun_ffi_test", "await_body_with_fin")
fn await_body_with_fin(body: BitArray) -> Result(BitArray, error.GluegunError)

@external(erlang, "gluegun_ffi_test", "await_body_with_trailers")
fn await_body_with_trailers(
  body: BitArray,
  trailers: List(#(String, String)),
) -> Result(BitArray, error.GluegunError)
