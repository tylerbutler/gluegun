import gleam/erlang/process
import gleam/http
import gleam/string
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/message
import gluegun/request
import gluegun/websocket

type Selected {
  Event(Result(message.Event, error.GluegunError))
  Command(Int)
}

pub fn selects_informational_response_tuples_test() -> Nil {
  use <- isolated
  let source = connection_handle()
  let reference = stream()
  assert_selected(
    inform(source, reference, 103, [#("LINK", "</style.css>")]),
    message.Envelope(
      source,
      reference,
      message.Inform(103, [#("link", "</style.css>")]),
    ),
  )
}

pub fn selects_data_tuples_test() -> Nil {
  use <- isolated
  let source = connection_handle()
  let reference = stream()
  assert_selected(
    data(source, reference, fin.Fin, <<"body":utf8>>),
    message.Envelope(source, reference, message.Data(fin.Fin, <<"body":utf8>>)),
  )
}

pub fn selects_trailer_tuples_test() -> Nil {
  use <- isolated
  let source = connection_handle()
  let reference = stream()
  assert_selected(
    trailers(source, reference, [#("X-Final", "yes")]),
    message.Envelope(source, reference, message.Trailers([#("x-final", "yes")])),
  )
}

pub fn selects_push_tuples_and_keeps_parent_and_child_streams_distinct_test() -> Nil {
  use <- isolated
  let source = connection_handle()
  let reference = stream()
  let child = stream()
  assert_selected(
    push(source, reference, child, "GET", "/asset", []),
    message.Envelope(
      source,
      reference,
      message.Push(child, http.Get, "/asset", []),
    ),
  )
}

pub fn selects_upgrade_tuples_test() -> Nil {
  use <- isolated
  let source = connection_handle()
  let reference = stream()
  assert_selected(
    upgrade(source, reference, ["websocket"], []),
    message.Envelope(source, reference, message.Upgrade(["websocket"], [])),
  )
}

fn assert_selected(raw: message.GunMessage, expected: message.Envelope) -> Nil {
  send_message(raw)
  let assert Ok(Ok(message.StreamMessage(envelope))) =
    process.selector_receive(selector(), 100)
  assert envelope == expected
}

pub fn composes_gun_events_with_application_subjects_test() -> Nil {
  use <- isolated
  let commands = process.new_subject()
  let selector =
    process.new_selector()
    |> process.select_map(commands, Command)
    |> message.select(Event)
  let source = connection_handle()
  let reference = stream()
  send_message(frame(source, reference, message.Text("hello")))
  process.send(commands, 42)
  let assert Ok(Event(Ok(message.StreamMessage(message.Envelope(
    received_source,
    received_stream,
    message.WebSocket(message.Text("hello")),
  ))))) = process.selector_receive(selector, 100)
  assert received_source == source
  assert received_stream == reference
  let assert Ok(Command(42)) = process.selector_receive(selector, 100)
  Nil
}

pub fn preserves_multiple_connection_and_stream_identities_test() -> Nil {
  use <- isolated
  let first = connection_handle()
  let second = other_connection()
  let first_stream = stream()
  let second_stream = stream()
  let selector = selector()
  send_message(response(first, first_stream))
  send_message(response(second, second_stream))
  let assert Ok(Ok(message.StreamMessage(first_envelope))) =
    process.selector_receive(selector, 100)
  let assert Ok(Ok(message.StreamMessage(second_envelope))) =
    process.selector_receive(selector, 100)
  assert first_envelope.connection == first
  assert first_envelope.stream == first_stream
  assert second_envelope.connection == second
  assert second_envelope.stream == second_stream
  assert first != second
  assert first_stream != second_stream
}

pub fn routes_stream_and_connection_errors_with_their_source_test() -> Nil {
  use <- isolated
  let source = connection_handle()
  let reference = stream()
  let selector = selector()
  let raw_stream_error = stream_error(source, reference, "failed")
  let raw_connection_error = connection_error(source, "failed")
  send_message(raw_stream_error)
  send_message(raw_connection_error)
  let assert Error(expected_stream_error) = message.decode(raw_stream_error)
  let assert Error(expected_connection_error) =
    message.decode(raw_connection_error)
  let assert Ok(Ok(message.StreamFailure(
    received_source,
    received_stream,
    failure,
  ))) = process.selector_receive(selector, 100)
  assert received_source == source
  assert received_stream == reference
  assert failure == expected_stream_error
  let assert Ok(Ok(message.ConnectionFailure(received_source, failure))) =
    process.selector_receive(selector, 100)
  assert received_source == source
  assert failure == expected_connection_error
}

pub fn decodes_http_up_down_and_tunnel_lifecycle_test() -> Nil {
  use <- isolated
  let source = connection_handle()
  let reference = stream()
  let selector = selector()
  send_message(up(source, "http2"))
  let assert Ok(Ok(message.ConnectionUp(received_source, message.Http2))) =
    process.selector_receive(selector, 100)
  assert received_source == source
  let raw_down = down(source, "http", "closed", [reference])
  let assert Error(expected_error) = message.decode(raw_down)
  send_message(raw_down)
  let assert Ok(Ok(message.ConnectionDown(
    received_source,
    message.Http1,
    failure,
    killed,
  ))) = process.selector_receive(selector, 100)
  assert received_source == source
  assert killed == [reference]
  assert failure == expected_error
  send_message(tunnel_up(source, reference, "http2"))
  let assert Ok(Ok(message.TunnelUp(
    received_source,
    received_stream,
    message.Http2,
  ))) = process.selector_receive(selector, 100)
  assert received_source == source
  assert received_stream == reference
}

pub fn decodes_websocket_raw_and_socks_lifecycle_protocols_test() -> Nil {
  let source = connection_handle()
  let assert Ok(message.ConnectionDown(
    _,
    message.WebSocketProtocol,
    error.ConnectionDown(_),
    [],
  )) = message.decode_event(down(source, "ws", "closed", []))
  let assert Ok(message.ConnectionUp(_, message.Raw)) =
    message.decode_event(up(source, "raw"))
  let assert Ok(message.TunnelUp(_, _, message.Socks)) =
    message.decode_event(tunnel_up(source, stream(), "socks"))
  Nil
}

pub fn preserves_source_for_malformed_stream_payloads_test() -> Nil {
  use <- isolated
  let source = connection_handle()
  let reference = stream()
  send_message(malformed_frame(source, reference))
  let assert Ok(Ok(message.StreamFailure(
    received_source,
    received_stream,
    error.DecodeError(_),
  ))) = process.selector_receive(selector(), 100)
  assert received_source == source
  assert received_stream == reference
  send_message(malformed_response(source, reference))
  let assert Ok(Ok(message.StreamFailure(
    received_source,
    received_stream,
    error.DecodeError(_),
  ))) = process.selector_receive(selector(), 100)
  assert received_source == source
  assert received_stream == reference
}

pub fn validates_tunnel_streams_and_lifecycle_fields_test() -> Nil {
  let source = connection_handle()
  let nested = tunnel_stream([stream(), stream()])
  let assert Ok(message.TunnelUp(_, received_stream, message.Http2)) =
    message.decode_event(tunnel_up(source, nested, "http2"))
  assert received_stream == nested
  let assert Ok(message.StreamFailure(_, received_stream, error.StreamError(_))) =
    message.decode_event(stream_error(source, nested, "failed"))
  assert received_stream == nested
  let assert Error(error.DecodeError(_)) =
    message.decode_event(tunnel_up(source, tunnel_stream([]), "http2"))
  let assert Error(error.DecodeError(_)) =
    message.decode_event(malformed_killed_streams(source))
  let assert Error(error.DecodeError(_)) =
    message.decode_event(malformed_protocol(source))
  Nil
}

pub fn rejects_invalid_sources_and_unknown_lifecycle_protocols_test() -> Nil {
  use <- isolated
  let assert Error(error.DecodeError(_)) =
    message.decode_event(invalid_identity())
  let assert Error(error.DecodeError(_)) =
    message.decode_event(up(connection_handle(), "unknown"))
  send_message(invalid_identity())
  let assert Ok(Error(error.DecodeError(_))) =
    process.selector_receive(selector(), 100)
  Nil
}

pub fn leaves_unselected_mail_and_external_down_messages_alone_test() -> Nil {
  use <- isolated
  let assert Ok(Nil) =
    with_unselected(fn() {
      let assert Error(Nil) = process.selector_receive(selector(), 0)
      Nil
    })
  Nil
}

pub fn composes_an_exact_connection_monitor_without_selecting_other_down_test() -> Nil {
  use <- isolated
  let source = other_connection()
  let monitor = connection.monitor(source)
  let selector =
    process.new_selector()
    |> message.select(Event)
    |> process.select_specific_monitor(monitor, fn(_) { Command(7) })
  let assert Ok(Command(7)) = process.selector_receive(selector, 100)
  process.demonitor_process(monitor)
  let assert Ok(Nil) =
    with_unselected(fn() {
      let assert Error(Nil) = process.selector_receive(selector, 0)
      Nil
    })
  Nil
}

pub fn rejects_an_envelope_from_another_socket_without_recording_test() -> Nil {
  let source = connection_handle()
  let reference = stream()
  let socket = websocket.socket(source, reference, connection.infinity())
  let assert Error(error.InvalidMessage(_)) =
    websocket.record_frame(
      socket,
      message.Envelope(
        other_connection(),
        reference,
        message.WebSocket(message.Close),
      ),
    )
  let assert Error(error.InvalidMessage(_)) =
    websocket.record_frame(
      socket,
      message.Envelope(source, stream(), message.WebSocket(message.Close)),
    )
  let assert Error(error.InvalidMessage(_)) =
    websocket.record_frame(
      socket,
      message.Envelope(source, reference, message.Trailers([])),
    )
  let assert Ok(message.Text("hello")) =
    websocket.record_frame(
      socket,
      message.Envelope(
        source,
        reference,
        message.WebSocket(message.Text("hello")),
      ),
    )
  Nil
}

pub fn records_a_selector_delivered_peer_close_before_socket_close_test() -> Nil {
  selector_close("peer_reason", False, 1)
}

pub fn restores_selector_delivered_finite_credit_before_close_test() -> Nil {
  selector_close("flow_coalesced", True, 3)
}

fn selector_close(mode: String, finite: Bool, frames: Int) -> Nil {
  use <- isolated
  let assert Ok(Nil) =
    with_server(mode, fn(port) {
      let assert Ok(timeout) = connection.milliseconds(500)
      let upgrade = case finite {
        True -> {
          let assert Ok(options) =
            websocket.upgrade_options() |> websocket.with_flow(1)
          options
        }
        False -> websocket.upgrade_options()
      }
      let assert Ok(socket) =
        websocket.connect(
          host: "127.0.0.1",
          port: port,
          path: "/echo",
          options: websocket.options()
            |> websocket.with_timeout(timeout)
            |> websocket.with_upgrade_options(upgrade),
        )
      record_frames(socket, selector(), frames)
      websocket.close(socket)
    })
  Nil
}

fn record_frames(
  socket: websocket.Socket,
  selector: process.Selector(Result(message.Event, error.GluegunError)),
  remaining: Int,
) -> Nil {
  case remaining {
    0 -> Nil
    _ -> {
      let assert Ok(Ok(message.StreamMessage(envelope))) =
        process.selector_receive(selector, 500)
      let assert Ok(_) = websocket.record_frame(socket, envelope)
      record_frames(socket, selector, remaining - 1)
    }
  }
}

pub fn receives_http_down_while_gun_remains_alive_to_retry_test() -> Nil {
  use <- isolated
  let assert Ok(Nil) =
    with_http_disconnect(fn(port) {
      let assert Ok(retries) = connection.retry_count(1)
      let assert Ok(timeout) = connection.milliseconds(1000)
      let assert Ok(source) =
        connection.options()
        |> connection.with_retry(retries)
        |> connection.with_protocols([connection.Http1])
        |> connection.open(host: "127.0.0.1", port: port)
      let assert Ok(connection.Http1) = connection.await_up(source, timeout)
      let assert Ok(_) =
        request.request(source, http.Get, "/", [], <<>>, request.options())
      await_http_down(source, selector())
      assert_alive(source)
      connection.terminate(source)
    })
  Nil
}

fn await_http_down(
  source: connection.Connection,
  selector: process.Selector(Result(message.Event, error.GluegunError)),
) -> Nil {
  let assert Ok(Ok(event)) = process.selector_receive(selector, 1000)
  case event {
    message.ConnectionDown(
      received_source,
      message.Http1,
      error.ConnectionDown(_),
      _,
    ) -> {
      assert received_source == source
      Nil
    }
    message.StreamMessage(_) -> await_http_down(source, selector)
    message.StreamFailure(received_source, _, _) -> {
      assert received_source == source
      await_http_down(source, selector)
    }
    message.ConnectionUp(_, _)
    | message.ConnectionDown(_, _, _, _)
    | message.TunnelUp(_, _, _)
    | message.ConnectionFailure(_, _) -> panic as string.inspect(event)
  }
}

fn selector() -> process.Selector(Result(message.Event, error.GluegunError)) {
  process.new_selector() |> message.select(fn(event) { event })
}

@external(erlang, "gluegun_selector_test", "isolated")
fn isolated(callback: fn() -> Nil) -> Nil

@external(erlang, "gluegun_ffi_test", "mailbox_inform_message")
fn inform(
  source: connection.Connection,
  stream: request.Stream,
  status: Int,
  headers: List(request.Header),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "mailbox_data_message")
fn data(
  source: connection.Connection,
  stream: request.Stream,
  fin: fin.Fin,
  body: BitArray,
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "mailbox_trailers_message")
fn trailers(
  source: connection.Connection,
  stream: request.Stream,
  headers: List(request.Header),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "mailbox_push_message")
fn push(
  source: connection.Connection,
  stream: request.Stream,
  child: request.Stream,
  method: String,
  path: String,
  headers: List(request.Header),
) -> message.GunMessage

@external(erlang, "gluegun_ffi_test", "mailbox_upgrade_message")
fn upgrade(
  source: connection.Connection,
  stream: request.Stream,
  protocols: List(String),
  headers: List(request.Header),
) -> message.GunMessage

@external(erlang, "gluegun_selector_test", "tunnel_stream")
fn tunnel_stream(streams: List(request.Stream)) -> request.Stream

@external(erlang, "gluegun_selector_test", "malformed_killed_streams")
fn malformed_killed_streams(source: connection.Connection) -> message.GunMessage

@external(erlang, "gluegun_selector_test", "malformed_protocol")
fn malformed_protocol(source: connection.Connection) -> message.GunMessage

@external(erlang, "gluegun_selector_test", "malformed_response")
fn malformed_response(
  source: connection.Connection,
  stream: request.Stream,
) -> message.GunMessage

@external(erlang, "gluegun_selector_test", "assert_alive")
fn assert_alive(connection: connection.Connection) -> Nil

@external(erlang, "gluegun_selector_test", "connection")
fn connection_handle() -> connection.Connection

@external(erlang, "gluegun_selector_test", "other_connection")
fn other_connection() -> connection.Connection

@external(erlang, "gluegun_selector_test", "stream")
fn stream() -> request.Stream

@external(erlang, "gluegun_selector_test", "send_message")
fn send_message(raw: message.GunMessage) -> Nil

@external(erlang, "gluegun_selector_test", "up")
fn up(source: connection.Connection, protocol: String) -> message.GunMessage

@external(erlang, "gluegun_selector_test", "down")
fn down(
  source: connection.Connection,
  protocol: String,
  reason: String,
  killed: List(request.Stream),
) -> message.GunMessage

@external(erlang, "gluegun_selector_test", "tunnel_up")
fn tunnel_up(
  source: connection.Connection,
  stream: request.Stream,
  protocol: String,
) -> message.GunMessage

@external(erlang, "gluegun_selector_test", "stream_error")
fn stream_error(
  source: connection.Connection,
  stream: request.Stream,
  reason: String,
) -> message.GunMessage

@external(erlang, "gluegun_selector_test", "connection_error")
fn connection_error(
  source: connection.Connection,
  reason: String,
) -> message.GunMessage

@external(erlang, "gluegun_selector_test", "frame")
fn frame(
  source: connection.Connection,
  stream: request.Stream,
  frame: message.Frame,
) -> message.GunMessage

@external(erlang, "gluegun_selector_test", "response")
fn response(
  source: connection.Connection,
  stream: request.Stream,
) -> message.GunMessage

@external(erlang, "gluegun_selector_test", "invalid_identity")
fn invalid_identity() -> message.GunMessage

@external(erlang, "gluegun_selector_test", "malformed_frame")
fn malformed_frame(
  source: connection.Connection,
  stream: request.Stream,
) -> message.GunMessage

@external(erlang, "gluegun_selector_test", "with_unselected")
fn with_unselected(callback: fn() -> Nil) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_selector_test", "with_http_disconnect")
fn with_http_disconnect(
  callback: fn(Int) -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)

@external(erlang, "gluegun_ws_close_test", "with_server")
fn with_server(
  mode: String,
  callback: fn(Int) -> Result(Nil, error.GluegunError),
) -> Result(Nil, error.GluegunError)
