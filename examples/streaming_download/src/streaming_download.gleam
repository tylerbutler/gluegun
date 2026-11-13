/// Response streaming with finite credit, a byte limit, and a total deadline.
import gleam/bit_array
import gleam/http
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/message
import gluegun/request

const host = "httpbin.org"

const port = 443

const path = "/stream/5"

// Example policy only. Choose a limit for your application.
const max_bytes = 1_048_576

type ClockUnit {
  Millisecond
}

@external(erlang, "erlang", "monotonic_time")
fn monotonic_time(unit: ClockUnit) -> Int

pub fn main() -> Nil {
  let deadline = monotonic_time(Millisecond) + 15_000
  let assert Ok(setup_timeout) = connection.milliseconds(1000)
  let assert Ok(retries) = connection.retry_count(0)

  case
    connection.options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.with_address_family(connection.Ipv4)
    |> connection.with_retry(retries)
    |> connection.with_domain_lookup_timeout(setup_timeout)
    |> connection.with_connect_timeout(setup_timeout)
    |> connection.with_tls_handshake_timeout(setup_timeout)
    |> connection.open(host: host, port: port)
  {
    Ok(connection) -> {
      case download(connection, deadline) {
        Ok(Nil) -> Nil
        Error(error) ->
          io.println("download failed: " <> error_to_string(error))
      }

      close(connection)
    }

    Error(error) -> io.println("connection failed: " <> error_to_string(error))
  }
}

fn download(
  connection: connection.Connection,
  deadline: Int,
) -> Result(Nil, error.GluegunError) {
  use timeout <- result.try(remaining_timeout(deadline))
  use protocol <- result.try(connection.await_up(connection, timeout))
  io.println("protocol: " <> protocol_to_string(protocol))

  use _ <- result.try(remaining_timeout(deadline))
  use options <- result.try(request.with_initial_flow(request.options(), 1))
  use stream <- result.try(request.request(
    connection,
    http.Get,
    path,
    [],
    <<>>,
    options,
  ))

  await_response(connection, stream, deadline)
}

fn await_response(
  connection: connection.Connection,
  stream: request.Stream,
  deadline: Int,
) -> Result(Nil, error.GluegunError) {
  use timeout <- result.try(remaining_timeout(deadline))
  case message.await(connection, stream, timeout) {
    Ok(message.Inform(_, _)) -> await_response(connection, stream, deadline)
    Ok(message.Response(response_fin, status, headers)) -> {
      use _ <- result.try(check_headers(status, headers))
      io.println("status: " <> int.to_string(status))
      io.println("headers: " <> int.to_string(count(headers)))

      case response_fin {
        fin.Fin -> Ok(Nil)
        fin.NoFin -> stream_body(connection, stream, deadline, 0)
      }
    }

    Ok(message.Data(_, _) as other)
    | Ok(message.Trailers(_) as other)
    | Ok(message.Push(_, _, _, _) as other)
    | Ok(message.Upgrade(_, _) as other)
    | Ok(message.WebSocket(_) as other) -> unexpected(other)
    Error(error) -> Error(error)
  }
}

fn stream_body(
  connection: connection.Connection,
  stream: request.Stream,
  deadline: Int,
  received: Int,
) -> Result(Nil, error.GluegunError) {
  use timeout <- result.try(remaining_timeout(deadline))
  case message.await(connection, stream, timeout) {
    Ok(message.Data(response_fin, data)) -> {
      let total = received + bit_array.byte_size(data)
      use _ <- result.try(case total <= max_bytes {
        True -> Ok(Nil)
        False -> Error(error.InvalidMessage("response exceeds byte limit"))
      })
      print_chunk(data)
      case response_fin {
        fin.Fin -> Ok(Nil)
        fin.NoFin -> {
          use _ <- result.try(remaining_timeout(deadline))
          use _ <- result.try(request.update_flow(connection, stream, 1))
          stream_body(connection, stream, deadline, total)
        }
      }
    }

    Ok(message.Trailers(headers)) -> {
      io.println("trailers: " <> int.to_string(count(headers)))
      Ok(Nil)
    }

    Ok(message.Inform(_, _) as other)
    | Ok(message.Response(_, _, _) as other)
    | Ok(message.Push(_, _, _, _) as other)
    | Ok(message.Upgrade(_, _) as other)
    | Ok(message.WebSocket(_) as other) -> unexpected(other)
    Error(error) -> Error(error)
  }
}

fn check_headers(
  status: Int,
  headers: List(request.Header),
) -> Result(Nil, error.GluegunError) {
  case status >= 200 && status < 300 {
    False -> Error(error.InvalidMessage("non-success response status"))
    True ->
      list.try_each(headers, fn(header) {
        case header {
          #("content-length", value) ->
            case int.parse(value) {
              Ok(size) if size >= 0 && size <= max_bytes -> Ok(Nil)
              Ok(_) | Error(_) ->
                Error(error.InvalidMessage(
                  "invalid or oversized Content-Length",
                ))
            }
          _ -> Ok(Nil)
        }
      })
  }
}

fn remaining_timeout(
  deadline: Int,
) -> Result(connection.Timeout, error.GluegunError) {
  let remaining = deadline - monotonic_time(Millisecond)
  case remaining > 0 {
    True -> connection.milliseconds(remaining)
    False -> Error(error.Timeout)
  }
}

fn print_chunk(data: BitArray) -> Nil {
  io.println("chunk bytes: " <> int.to_string(bit_array.byte_size(data)))
}

fn close(connection: connection.Connection) -> Nil {
  case connection.terminate(connection) {
    Ok(Nil) -> Nil
    Error(error) -> io.println("close failed: " <> error_to_string(error))
  }
}

fn unexpected(message: message.Message) -> Result(Nil, error.GluegunError) {
  Error(error.InvalidMessage(
    "unexpected message: " <> message_to_string(message),
  ))
}

fn protocol_to_string(protocol: connection.Protocol) -> String {
  case protocol {
    connection.Http1 -> "HTTP/1.1"
    connection.Http2 -> "HTTP/2"
  }
}

fn count(items: List(a)) -> Int {
  list.length(items)
}

fn message_to_string(message: message.Message) -> String {
  case message {
    message.Inform(status, _) -> "Inform(" <> int.to_string(status) <> ")"
    message.Response(_, status, _) ->
      "Response(" <> int.to_string(status) <> ")"
    message.Data(_, data) ->
      "Data(" <> int.to_string(bit_array.byte_size(data)) <> " bytes)"
    message.Trailers(headers) ->
      "Trailers(" <> int.to_string(count(headers)) <> " headers)"
    message.Push(_, method, uri, _) ->
      "Push(" <> request.method_to_string(method) <> " " <> uri <> ")"
    message.Upgrade(protocols, _) ->
      "Upgrade(" <> int.to_string(count(protocols)) <> " protocols)"
    message.WebSocket(frame) -> "WebSocket(" <> frame_to_string(frame) <> ")"
  }
}

fn frame_to_string(frame: message.Frame) -> String {
  case frame {
    message.Text(_) -> "Text"
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

fn error_to_string(error: error.GluegunError) -> String {
  case error {
    error.Timeout -> "timeout"
    error.ConnectionDown(reason) -> "connection down: " <> reason
    error.ConnectionError(reason) -> "connection error: " <> reason
    error.StreamError(reason) -> "stream error: " <> reason
    error.InvalidOptions(reason) -> "invalid options: " <> reason
    error.InvalidMessage(reason) -> "invalid message: " <> reason
    error.ErlangError(reason) -> "erlang error: " <> reason
    error.DecodeError(reason) -> "decode error: " <> reason
    error.UnsupportedFeature(reason) -> "unsupported feature: " <> reason
  }
}
