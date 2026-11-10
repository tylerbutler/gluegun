import gleam/http
import gleam/list
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/message
import gluegun/request
import gluegun/tls

pub fn tls_http2_alpn_cancel_sends_rst_cancel_and_reuses_the_connection_test() -> Nil {
  let assert Ok(Nil) =
    with_tls_cancel_server(fn(port, cas) {
      let assert Ok(conn) =
        connection.options()
        |> connection.with_address_family(connection.Ipv4)
        |> connection.with_protocols([connection.Http2, connection.Http1])
        |> connection.with_tls_options(tls.options() |> tls.with_cacerts(cas))
        |> connection.open(host: "localhost", port: port)
      with_connection(conn, fn() {
        let assert Ok(connection.Http2) = connection.await_up(conn, timeout())
        let assert Ok(flow) = request.options() |> request.with_initial_flow(1)
        let assert Ok(stream) =
          request.request(conn, http.Get, "/cancel", [], <<>>, flow)
        let assert Ok(message.Response(fin.NoFin, 200, _)) =
          message.await(conn, stream, timeout())
        let assert Ok(message.Data(fin.NoFin, <<"paused":utf8>>)) =
          message.await(conn, stream, timeout())
        let assert Ok(Nil) = request.cancel(conn, stream)
        // The peer will not answer this request until it observes the exact
        // RST_STREAM CANCEL (0x8) for the first stream on this TLS socket.
        let assert Ok(next) =
          request.request(conn, http.Get, "/reuse", [], <<>>, request.options())
        let assert Ok(message.Response(fin.NoFin, 200, _)) =
          message.await(conn, next, timeout())
        let assert Ok(message.Data(fin.Fin, <<"reused":utf8>>)) =
          message.await(conn, next, timeout())
        connection.terminate(conn)
      })
    })
  Nil
}

pub fn cancelled_flow_paused_http1_is_safely_terminated_and_replaced_test() -> Nil {
  let assert Ok(Nil) =
    with_http1_replacement_server(fn(port, peer) {
      let options =
        connection.options() |> connection.with_protocols([connection.Http1])
      let assert Ok(old) =
        connection.open(options, host: "127.0.0.1", port: port)
      with_connection(old, fn() {
        let assert Ok(connection.Http1) = connection.await_up(old, timeout())
        let assert Ok(flow) = request.options() |> request.with_initial_flow(1)
        let assert Ok(stream) =
          request.request(old, http.Get, "/paused", [], <<>>, flow)
        let assert Ok(message.Response(fin.NoFin, 200, _)) =
          message.await(old, stream, timeout())
        let assert Ok(message.Data(fin.NoFin, <<"first":utf8>>)) =
          message.await(old, stream, timeout())
        // The peer confirms the remaining bytes are now on the wire. With
        // credit exhausted they must not be delivered before cancellation.
        let assert Ok(Nil) = release_remainder(peer)
        let assert Ok(short) = connection.milliseconds(50)
        let assert Error(error.Timeout) = message.await(old, stream, short)
        let assert Ok(Nil) = request.cancel(old, stream)
        let assert Ok(Nil) = connection.terminate(old)
        let assert Ok(Nil) = assert_released(old)
        // #78 is accepted: do not ask the old connection to recover. Open a
        // distinct process; the peer requires closure of the old TCP socket.
        let assert Ok(replacement) =
          connection.open(options, host: "127.0.0.1", port: port)
        with_connection(replacement, fn() {
          let assert True = replacement != old
          let assert Ok(connection.Http1) =
            connection.await_up(replacement, timeout())
          let assert Ok(next) =
            request.request(
              replacement,
              http.Get,
              "/replacement",
              [],
              <<>>,
              request.options(),
            )
          let assert Ok(message.Response(fin.NoFin, 200, _)) =
            message.await(replacement, next, timeout())
          let assert Ok(message.Data(fin.Fin, <<"replacement":utf8>>)) =
            message.await(replacement, next, timeout())
          connection.terminate(replacement)
        })
      })
    })
  Nil
}

pub fn rejects_invalid_inbound_header_names_on_every_message_test() -> Nil {
  malformed_headers("name")
}

pub fn rejects_invalid_inbound_header_values_on_every_message_test() -> Nil {
  malformed_headers("value")
}

pub fn rejects_incomplete_inbound_utf8_on_every_message_test() -> Nil {
  malformed_headers("incomplete")
}

pub fn rejects_malformed_inbound_header_pairs_on_every_message_test() -> Nil {
  malformed_headers("shape")
}

pub fn rejects_nontext_inbound_header_values_on_every_message_test() -> Nil {
  malformed_headers("term")
}

pub fn rejects_malformed_inbound_values_as_decode_errors_test() -> Nil {
  list.each(["fin", "data", "frame", "frame_shape", "status"], fn(kind) {
    malformed(kind, "value")
  })
}

pub fn rejects_invalid_utf8_in_push_and_upgrade_strings_test() -> Nil {
  list.each(["uri", "method", "protocol", "protocol_shape"], fn(kind) {
    malformed(kind, "value")
  })
}

fn malformed_headers(fault: String) -> Nil {
  list.each(["inform", "response", "trailers", "push", "upgrade"], fn(kind) {
    malformed(kind, fault)
  })
}

fn malformed(kind: String, fault: String) -> Nil {
  let #(conn, stream, raw) = incoming(kind, fault)
  let assert Error(error.DecodeError(_)) = message.decode(raw)
  let assert Error(error.DecodeError(_)) =
    message.await(conn, stream, timeout())
  Nil
}

pub fn preserves_valid_utf8_header_values_without_transcoding_test() -> Nil {
  let #(conn, stream, raw) = incoming("response", "valid")
  let assert Ok(envelope) = message.decode(raw)
  let assert message.Response(fin.Fin, 200, [#("x-test", "café")]) =
    envelope.message
  let assert Ok(message.Response(fin.Fin, 200, [#("x-test", "café")])) =
    message.await(conn, stream, timeout())
  Nil
}

pub fn public_flush_drains_seven_field_pushes_and_preserves_other_mail_test() -> Nil {
  let #(conn, other) = flush_fixture()
  let assert Ok(Nil) = request.flush(conn)
  let assert Ok(Nil) = assert_flush(conn, other)
  Nil
}

pub fn rejects_streaming_content_length_before_any_cast_test() -> Nil {
  let #(conn, _, _) = incoming("response", "valid")
  // Drain this fixture message; only outgoing casts are inspected below.
  let assert Ok(Nil) = request.flush(conn)
  list.each(["0", "1", "100"], fn(length) {
    let assert Error(error.InvalidOptions(_)) =
      request.start_stream(
        conn,
        http.Post,
        "/",
        [#("Content-Length", length)],
        request.options(),
      )
    let assert True = no_cast()
  })
}

pub fn rejected_fixed_length_stream_keeps_wire_clean_and_connection_reusable_test() -> Nil {
  with_payload_server(False, fn(server, port) {
    let assert Ok(conn) =
      connection.options()
      |> connection.with_protocols([connection.Http1])
      |> connection.open(host: "127.0.0.1", port: port)
    with_payload_connection(conn, fn() {
      list.each(["0", "10"], fn(length) {
        let assert Error(error.InvalidOptions(_)) =
          request.start_stream(
            conn,
            http.Post,
            "/must-not-reach-peer",
            [#("Content-Length", length)],
            request.options(),
          )
      })
      let assert Ok(stream) =
        request.start_stream(conn, http.Post, "/chunked", [], request.options())
      let assert Ok(Nil) = request.data(conn, stream, fin.NoFin, <<"hel":utf8>>)
      let assert Ok(Nil) = request.data(conn, stream, fin.Fin, <<"lo":utf8>>)
      let assert Ok(#("/chunked", <<"hello":utf8>>)) = await_http(server)
      let assert Ok(message.Response(_, 200, _)) =
        message.await(conn, stream, timeout())
      let assert Ok(<<"hello":utf8>>) =
        message.await_body(conn, stream, timeout())
      list.each([#("0", <<>>), #("2", <<"ok":utf8>>)], fn(entry) {
        let #(length, body) = entry
        let assert Ok(whole) =
          request.request(
            conn,
            http.Post,
            "/whole",
            [#("Content-Length", length)],
            body,
            request.options(),
          )
        let assert Ok(#("/whole", received)) = await_http(server)
        let assert True = received == body
        let assert Ok(message.Response(_, 200, _)) =
          message.await(conn, whole, timeout())
        case body {
          <<>> -> Nil
          _ -> {
            let assert Ok(received) = message.await_body(conn, whole, timeout())
            let assert True = received == body
            Nil
          }
        }
      })
      Nil
    })
  })
}

pub fn verifying_tls_rejects_disabled_sni_before_open_test() -> Nil {
  list.each(
    [tls.options(), tls.options() |> tls.with_verify(tls.VerifyPeer)],
    fn(options) {
      let assert Error(error.InvalidOptions(_)) =
        connection.options()
        |> connection.with_tls_options(
          options |> tls.with_server_name_indication(tls.Disable),
        )
        |> connection.open(host: "localhost", port: 1)
    },
  )
}

pub fn monotonic_clock_crosses_the_boundary_as_int_test() -> Nil {
  let #(before, after) = monotonic_pair()
  let assert True = after >= before
  Nil
}

pub fn rejects_invalid_utf8_response_headers_from_the_wire_test() -> Nil {
  wire_decode_error(
    <<
      "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nX-Test: ":utf8,
      255,
      "\r\n\r\n":utf8,
    >>,
    False,
  )
}

pub fn rejects_invalid_utf8_trailers_from_the_wire_test() -> Nil {
  wire_decode_error(
    <<
      "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\nX-Test: ":utf8,
      255,
      "\r\n\r\n":utf8,
    >>,
    True,
  )
}

fn wire_decode_error(response: BitArray, trailer: Bool) -> Nil {
  let assert Ok(Nil) =
    with_response(response, fn(port) {
      let assert Ok(conn) =
        connection.options()
        |> connection.with_protocols([connection.Http1])
        |> connection.open(host: "127.0.0.1", port: port)
      let assert Ok(connection.Http1) = connection.await_up(conn, timeout())
      let assert Ok(stream) =
        request.request(conn, http.Get, "/", [], <<>>, request.options())
      case trailer {
        True -> {
          let assert Ok(message.Response(_, 200, _)) =
            message.await(conn, stream, timeout())
          Nil
        }
        False -> Nil
      }
      let result = message.await(conn, stream, timeout())
      let cleanup = connection.terminate(conn)
      let assert Error(error.DecodeError(_)) = result
      cleanup
    })
  Nil
}

fn timeout() -> connection.Timeout {
  let assert Ok(timeout) = connection.milliseconds(500)
  timeout
}

@external(erlang, "gluegun_runtime_regression_test", "incoming")
fn incoming(
  kind: String,
  fault: String,
) -> #(connection.Connection, request.Stream, message.GunMessage)

@external(erlang, "gluegun_runtime_regression_test", "flush_fixture")
fn flush_fixture() -> #(connection.Connection, connection.Connection)

@external(erlang, "gluegun_runtime_regression_test", "assert_flush")
fn assert_flush(
  conn: connection.Connection,
  other: connection.Connection,
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_runtime_regression_test", "no_cast")
fn no_cast() -> Bool

@external(erlang, "gluegun_runtime_regression_test", "monotonic_pair")
fn monotonic_pair() -> #(Int, Int)

@external(erlang, "gluegun_runtime_regression_test", "with_response")
fn with_response(
  response: BitArray,
  callback: fn(Int) -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

type PayloadServer

@external(erlang, "gluegun_payload_server_test", "with_server")
fn with_payload_server(
  websocket: Bool,
  callback: fn(PayloadServer, Int) -> Nil,
) -> Nil

@external(erlang, "gluegun_payload_server_test", "with_connection")
fn with_payload_connection(
  conn: connection.Connection,
  callback: fn() -> Nil,
) -> Nil

@external(erlang, "gluegun_payload_server_test", "await_http")
fn await_http(server: PayloadServer) -> Result(#(String, BitArray), String)

@external(erlang, "gluegun_http2_test", "with_tls_cancel_server")
fn with_tls_cancel_server(
  callback: fn(Int, List(BitArray)) -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_runtime_regression_test", "with_connection")
fn with_connection(
  conn: connection.Connection,
  callback: fn() -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

type ReplacementPeer

@external(erlang, "gluegun_runtime_regression_test", "with_http1_replacement_server")
fn with_http1_replacement_server(
  callback: fn(Int, ReplacementPeer) -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_runtime_regression_test", "release_remainder")
fn release_remainder(peer: ReplacementPeer) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ws_close_test", "assert_released")
fn assert_released(
  conn: connection.Connection,
) -> Result(Nil, error.GluegunError)
