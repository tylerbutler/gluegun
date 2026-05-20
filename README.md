# Gluegun

[![Package Version](https://img.shields.io/hexpm/v/gluegun)](https://hex.pm/packages/gluegun)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gluegun/)
[![CI](https://github.com/tylerbutler/gluegun/actions/workflows/ci.yml/badge.svg)](https://github.com/tylerbutler/gluegun/actions/workflows/ci.yml)

A Gleam wrapper for the Erlang [Gun](https://ninenines.eu/docs/en/gun/) HTTP client.

Gun is an asynchronous HTTP client supporting HTTP/1.1, HTTP/2, and WebSocket over HTTP/1.1. Gluegun gives Gleam callers typed connection, request, response, message, and WebSocket helpers while preserving access to Gun's stream-oriented model. Because Gun is Erlang-only, Gluegun targets the Erlang runtime.

## Installation

```sh
gleam add gluegun
```

## Compatibility

- Erlang target only; Gluegun wraps the Erlang Gun client and does not support the JavaScript target.
- Supports Gleam `>= 1.7.0` and Gun `>= 2.1.0 and < 3.0.0`.

## Basic GET

Open a Gun connection, wait for it to be ready, send a GET, and collect the full response in memory.

```gleam
import gleam/int
import gleam/io
import gluegun/client
import gluegun/connection
import gluegun/request
import gluegun/response

pub fn main() {
  let timeout = connection.Milliseconds(5000)

  let assert Ok(conn) =
    connection.options()
    |> connection.open(host: "example.com", port: 80)
  let assert Ok(_protocol) = connection.await_up(conn, timeout)

  let assert Ok(res) =
    client.new(request.Get, "/")
    |> client.with_timeout(timeout: timeout)
    |> client.send(connection: conn)

  io.println("status: " <> int.to_string(response.status(res)))

  case response.body_text(res) {
    Ok(text) -> io.println(text)
    Error(_) -> io.println("response body was not UTF-8")
  }

  let assert Ok(Nil) = connection.close(conn)
}
```

## One-shot helper on an existing connection

`gluegun/client` helpers are one-shot per request: they send one request on an existing connection and collect that response. Gluegun does not parse URLs; pass the host and port to `connection.open`, then pass a path to request helpers.

```gleam
import gluegun/client
import gluegun/request

fn fetch_json(conn, path, timeout) {
  client.new(request.Get, path)
  |> client.with_header(name: "accept", value: "application/json")
  |> client.with_timeout(timeout: timeout)
  |> client.send(connection: conn)
}
```

## Streaming a request body

Use `gluegun/request` when the request body is produced in chunks. Start with `request.start_stream`, send zero or more chunks with `fin.NoFin`, and complete the body with `fin.Fin`. Response headers and body are separate asynchronous Gun stream messages; use `gluegun/message` helpers or your own receive loop for advanced flows.

```gleam
import gluegun/connection
import gluegun/fin
import gluegun/message
import gluegun/request

pub fn upload_chunks(conn) {
  let timeout = connection.Milliseconds(5000)

  let assert Ok(stream) =
    request.start_stream(
      conn,
      request.Post,
      "/upload",
      [#("content-type", "text/plain")],
      request.options(),
    )

  let assert Ok(Nil) = request.data(conn, stream, fin.NoFin, <<"first ":utf8>>)
  let assert Ok(Nil) = request.data(conn, stream, fin.Fin, <<"last":utf8>>)

  // Await the final response headers, then consume the response body.
  let assert Ok(message.Response(response_fin, _status, _headers)) =
    await_final_response(conn, stream, timeout)

  case response_fin {
    fin.Fin -> <<>>
    fin.NoFin -> {
      let assert Ok(body) = message.await_body(conn, stream, timeout)
      body
    }
  }
}

fn await_final_response(conn, stream, timeout) {
  case message.await(conn, stream, timeout) {
    Ok(message.Inform(_status, _headers)) ->
      await_final_response(conn, stream, timeout)
    other -> other
  }
}
```

If you need response chunks or trailers as they arrive, continue awaiting
`message.Data` and `message.Trailers` with `message.await` instead of collecting
the full body with `message.await_body`.

## Prefer HTTP/2

Use TLS and put `Http2` before `Http1` to prefer HTTP/2 while allowing Gun to fall back to HTTP/1.1 when needed.

```gleam
import gluegun/client
import gluegun/connection

pub fn get_over_http2() {
  let options =
    connection.options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.with_protocols(protocols: [connection.Http2, connection.Http1])

  let assert Ok(conn) =
    options
    |> connection.open(host: "example.com", port: 443)
  let assert Ok(protocol) =
    connection.await_up(conn, connection.Milliseconds(5000))

  case protocol {
    connection.Http2 -> Nil
    connection.Http1 -> Nil
  }

  client.get(conn, "/", [], connection.Milliseconds(5000))
}
```

## WebSocket echo

Gun supports WebSocket over HTTP/1.1 only. Gluegun's high-level WebSocket options default to HTTP/1.1, and the low-level `upgrade_with_protocol` helpers reject HTTP/2 before calling Gun.

Use the reusable `Socket` API when you want explicit lifecycle control.

```gleam
import gleam/io
import gluegun/message
import gluegun/websocket

pub fn echo() {
  let assert Ok(socket) =
    websocket.connect(
      host: "localhost",
      port: 8080,
      path: "/echo",
      options: websocket.options(),
    )

  let assert Ok(Nil) = websocket.send_text(socket, "hello")

  case websocket.receive_app_frame(socket) {
    Ok(message.Text(reply)) -> io.println(reply)
    Ok(_) -> io.println("received a non-text frame")
    Error(_) -> io.println("websocket receive failed")
  }

  let assert Ok(Nil) = websocket.send_close_frame(socket)
}
```

For shorter one-shot flows, `with_socket` opens the socket, runs a callback, then closes the WebSocket and connection.

```gleam
import gleam/io
import gluegun/message
import gluegun/websocket

pub fn echo_once() {
  let assert Ok(message.Text(reply)) =
    websocket.with_socket(
      host: "localhost",
      port: 8080,
      path: "/echo",
      options: websocket.options(),
      callback: fn(socket) {
        let assert Ok(Nil) = websocket.send_text(socket, "hello")
        websocket.receive_app_frame(socket)
      },
    )

  io.println(reply)
}
```

`Socket` is reusable and lifecycle-explicit. `with_socket` is convenience-only for scoped use. Low-level `upgrade_with_protocol_and_options`, `send`, and `receive` remain available for advanced flows. The root facade stays intentionally minimal; import `gluegun/websocket` directly for `send_text`, `receive_app_frame`, `send_close_frame`, and `with_socket`.

See `examples/websocket_echo` for a fuller documentation-only WebSocket example.

## Error handling

Effectful operations return `Result(_, error.GluegunError)`. Pattern match on variants that matter to your application and keep a fallback for unexpected Erlang or decode errors. Pure builders and accessors return plain values.

```gleam
import gleam/io
import gluegun/client
import gluegun/connection
import gluegun/error

fn safe_get(conn) {
  case client.get(conn, "/", [], connection.Milliseconds(5000)) {
    Ok(response) -> Ok(response)
    Error(error.Timeout) -> {
      io.println("request timed out")
      Error(error.Timeout)
    }
    Error(error.ConnectionDown(reason)) -> {
      io.println("connection down: " <> reason)
      Error(error.ConnectionDown(reason))
    }
    Error(other) -> {
      io.println("request failed")
      Error(other)
    }
  }
}
```

## Limitations

- Erlang target only. Gluegun wraps Erlang Gun and is not available on the JavaScript target.
- Gun process ownership matters. Requests and WebSocket frames are asynchronous messages sent to the process that owns or awaits the Gun stream unless request options redirect replies.
- `client` helpers collect full response bodies in memory. Use low-level `request` and `message` APIs for streaming or advanced Gun flows.
- WebSocket over HTTP/2 is unsupported by Gun. Gluegun rejects it in `websocket.upgrade_with_protocol`.
- TLS option surface is intentionally small at first. Advanced TLS options may require future typed additions.

## Examples

Examples under `examples/` are source-level documentation, not standalone Gleam packages built by the root `just` tasks. Copy an example into a Gleam project and add `gluegun` as a dependency to run it.

## Development

```sh
just deps         # Download dependencies
just build        # Build project
just test         # Run tests
just format       # Format src/ and test/
just format-check # Check formatting
just check        # Type check
just docs         # Build documentation
just ci           # Run all CI checks
just main         # Run CI checks and build docs
```

Before publishing a release, run `just ci`, `gleam docs build`, and `gleam publish --dry-run` when supported by your installed Gleam version.

## License

MIT
