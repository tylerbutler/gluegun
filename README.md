# Gluegun

[![Hex version](https://img.shields.io/hexpm/v/gluegun)](https://hex.pm/packages/gluegun)
[![Docs](https://img.shields.io/badge/docs-gluegun.tylerbutler.com-ffaff3)](https://gluegun.tylerbutler.com/)
[![CI](https://github.com/tylerbutler/gluegun/actions/workflows/ci.yml/badge.svg)](https://github.com/tylerbutler/gluegun/actions/workflows/ci.yml)

Gluegun lets Gleam programs use [Gun](https://ninenines.eu/docs/en/gun/), the
Erlang HTTP client, through typed functions. Gun speaks HTTP/1.1, HTTP/2, and
WebSocket over HTTP/1.1, and it delivers each response as a series of
asynchronous messages. Gluegun keeps that stream model but gives each part a
Gleam type: connections, requests, responses, messages, and WebSocket frames.
Because Gun runs only on the BEAM, Gluegun supports only the Erlang target.

## Installation

Add Gluegun and `gleam_http` to `gleam.toml`. The examples below use standard
HTTP types such as `http.Get` from `gleam_http`, so most projects need both:

```toml
[dependencies]
gleam_http = ">= 4.0.0 and < 5.0.0"
gluegun = ">= 1.0.0 and < 2.0.0"
```

Then download the dependencies:

```sh
gleam deps download
```

`gleam add gluegun@1 gleam_http@4` does both steps in one command.

To use unreleased work, point the dependency at the Git repository instead.
A tag or commit SHA gives a build that you can repeat; `ref = "main"` follows
the latest revision:

```toml
gluegun = { git = "https://github.com/tylerbutler/gluegun.git", ref = "v1.0.0" }
```

Run `gleam deps download` again after you change the dependency.

Gluegun supports Gleam `>= 1.11.0`, Erlang/OTP 27 or later, and Gun
`>= 2.1.0 and < 3.0.0`. The API documentation is on the
[website](https://gluegun.tylerbutler.com/reference/) and on
[HexDocs](https://hexdocs.pm/gluegun/).

## Send a GET request

Each Gluegun exchange has the same shape. You open a connection to a host and
port, wait for Gun to negotiate a protocol, send requests on that connection,
and then release it. This example does each step once:

```gleam
import gleam/http
import gleam/int
import gleam/io
import gleam/result
import gluegun/client
import gluegun/connection
import gluegun/response

pub fn main() {
  use timeout <- result.try(connection.milliseconds(5000))

  use conn <- result.try(
    connection.options()
    |> connection.open(host: "example.com", port: 80),
  )
  let exchange = {
    use _protocol <- result.try(connection.await_up(conn, timeout))
    client.new(http.Get, "/")
    |> client.with_timeout(timeout: timeout)
    |> client.send(connection: conn)
  }
  let cleanup = connection.terminate(conn)
  use res <- result.try(exchange)
  use _ <- result.try(cleanup)

  io.println("status: " <> int.to_string(res.response.status))

  case response.body_text(res) {
    Ok(text) -> io.println(text)
    Error(_) -> io.println("response body was not UTF-8")
  }

  Ok(Nil)
}
```
The example creates `cleanup` before it examines either result, so the
connection is released even when the exchange fails. `terminate` also stops a
connection whose setup failed or stalled. If both steps fail, the exchange
error takes precedence. If only cleanup fails, its error is returned.

A lost connection stays lost unless you ask for more: connection options
default to zero retries. Call `connection.with_retry` to opt in to HTTP
reconnection. Even with retries, call `connection.terminate` after an
`await_up` error to release a process that is still alive.

Blocking `connection.await_up` consumes this connection's queued `gun_up` and
`gun_down` events and uses the latest event. An up followed by a down does not
report ready; a latest up can succeed with a zero timeout. Down events do not
restart the wait budget. Readiness does not guarantee that the socket stays open.

`client` helpers drain these lifecycle events before dispatch and after
completion, including failures. Each drain covers mail queued when it starts;
new deliveries cannot keep the helper in the drain. Later events can remain
queued. The helpers preserve stream messages and unrelated mail. Call blocking
helpers from the receiving process; use an actor receive loop instead if you
need to observe lifecycle events. Gluegun does not drain idle owners. With retry
enabled, events can collect until the next blocking call. Gun resets its retry
count after each established disconnect, so this count does not limit the
number of reconnect cycles. Reconnection does not replay failed requests or
restore WebSockets.

## Send requests on an open connection

In that example, the connection holds the host and port, and the request holds
only a path. Gluegun does not parse URLs. If you start with a full URL, parse
it with the standard `gleam/uri` module. Give the host and port to
`connection.open`, and give the path and query to the request. Gluegun sends
the request target as you give it, so encode it first, for example
`/items?tag=a%2Fb&tag=c`.

The `client` builder adds headers and a timeout to that path, then sends one
request and collects its response:

```gleam
import gleam/http
import gluegun/client

fn fetch_json(conn, path, timeout) {
  client.new(http.Get, path)
  |> client.with_header(name: "accept", value: "application/json")
  |> client.with_timeout(timeout: timeout)
  |> client.send(connection: conn)
}
```
`client.with_timeout` sets one budget for the full exchange, from dispatch to
the last body chunk. Informational responses and body chunks do not restart
it, and `Infinity` has no limit. If the budget has already expired, including
a budget of zero, the call returns `Timeout` and sends nothing. A timeout that
expires later cannot undo a request that Gun has already sent. Request bodies
are byte-aligned `BitArray` values and need not be UTF-8.

`client.send` returns a `gluegun/response.Response(BitArray)`. Its `response`
field is a standard `gleam/http/response.Response(BitArray)`, so the usual
header and body helpers work on it. The outer value also keeps the trailers
and the ordered `1xx` informational responses. To decode the body without
losing that metadata, map the inner response and rebuild the outer value:

```gleam
import gleam/bit_array
import gleam/http/response as http_response
import gleam/result
import gluegun/response

fn decode_body(collected: response.Response(BitArray)) {
  use decoded <- result.try(
    http_response.try_map(collected.response, bit_array.to_string),
  )
  Ok(response.Response(..collected, response: decoded))
}
```
Collection can fail, for example when the timeout expires. The client then
tries to cancel that stream and drain its queued messages, and it does the
same for any stream that the server pushed with it. It returns the original
error and keeps the connection and its other streams open; a cleanup failure
only produces a warning. Cancellation is asynchronous, so a message in transit
can arrive after the drain. If you need strict mailbox isolation, use the
low-level API in a separate receiving process.

## Use the root module for short programs

For a short program, the root `gluegun` module puts the common steps behind
one import: options, timeouts, open and await, request and send, body text,
and close, shutdown, or terminate. When you need custom headers, streaming,
or WebSockets, use the named modules.

```gleam
import gleam/http
import gleam/result
import gluegun

pub fn fetch() {
  use timeout <- result.try(gluegun.milliseconds(5000))
  use conn <- result.try(
    gluegun.open(gluegun.connection_options(), host: "localhost", port: 8080),
  )
  let exchange = {
    use _ <- result.try(gluegun.await_up(conn, timeout))
    use res <- result.try(
      gluegun.new_request(http.Get, "/") |> gluegun.send(connection: conn),
    )
    gluegun.body_text(res)
  }
  let cleanup = gluegun.terminate(conn)
  use text <- result.try(exchange)
  use _ <- result.try(cleanup)
  Ok(text)
}
```
## Stream a request body

The client collects the full response in memory. When you must produce a body
in pieces, or read a response as it arrives, use `gluegun/request` and
`gluegun/message`. Start the request with `request.start_stream`, send zero
or more chunks marked `fin.NoFin`, and mark the last chunk `fin.Fin`. Gun then
delivers the response as separate messages: zero or more informational
responses, then the final headers, then the body.

Do not set `Content-Length` on a streamed upload. Supported Gun versions can
crash on fixed-length chunk sequences, so Gluegun rejects the header before it
sends anything. If you know the length, send the complete body in one request.

This example skips informational responses such as `103 Early Hints`, then
collects the body:

```gleam
import gleam/http
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/message
import gluegun/request
import gleam/result

pub fn upload_chunks(
  conn: connection.Connection,
) -> Result(BitArray, error.GluegunError) {
  use timeout <- result.try(connection.milliseconds(5000))

  use stream <- result.try(
    request.start_stream(
      conn,
      http.Post,
      "/upload",
      [#("content-type", "text/plain")],
      request.options(),
    ),
  )

  use _ <- result.try(request.data(conn, stream, fin.NoFin, <<"first ":utf8>>))
  use _ <- result.try(request.data(conn, stream, fin.Fin, <<"last":utf8>>))

  use response <- result.try(await_final_response(conn, stream, timeout))

  case response {
    message.Response(fin.NoFin, _status, _headers) ->
      message.await_body(conn, stream, timeout)
    message.Response(fin.Fin, _status, _headers) -> Ok(<<>>)
    _ -> Error(error.InvalidMessage("expected a final response message"))
  }
}

fn await_final_response(
  conn: connection.Connection,
  stream: request.Stream,
  timeout: connection.Timeout,
) -> Result(message.Message, error.GluegunError) {
  case message.await(conn, stream, timeout) {
    Ok(message.Inform(_status, _headers)) ->
      await_final_response(conn, stream, timeout)
    other -> other
  }
}
```
To process response chunks or trailers as they arrive, replace
`message.await_body` with a loop over `message.await` that handles
`message.Data` and `message.Trailers`.

Such a loop can also bound memory. Set `request.with_initial_flow(options, 1)`
before you send the request, so that Gun delivers one data message at a time.
Check the status and `Content-Length`, count the bytes of each `message.Data`
chunk before you keep it, then grant the next message with
`request.update_flow(conn, stream, 1)`. Credit counts messages, not bytes or
allocations, so your loop must enforce the byte limit.

A bounded download also needs a bounded setup.
`with_domain_lookup_timeout`, `with_connect_timeout`, and
`with_tls_handshake_timeout` limit each setup stage, and
`connection.with_address_family` selects IPv4 or IPv6 without fallback. None
of them changes the TLS verification defaults. Stage limits are not a total
deadline, so measure one monotonic deadline across setup and every receive.
When it expires, `connection.terminate` stops the connection, waits for it to
exit, and flushes its messages from your mailbox.

`examples/streaming_download` and the
[streaming guide](https://gluegun.tylerbutler.com/guides/streaming/) show the
complete receive loop and the limits of Gun flow control.

## Prefer HTTP/2

HTTP/2 needs TLS, because the server selects the protocol during the TLS
handshake (ALPN). Put `Http2` before `Http1` to offer HTTP/2 first and let Gun
fall back to HTTP/1.1:

```gleam
import gleam/result
import gluegun/client
import gluegun/connection

pub fn get_over_http2() {
  use timeout <- result.try(connection.milliseconds(5000))
  let options =
    connection.options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.with_protocols(protocols: [connection.Http2, connection.Http1])

  use conn <- result.try(
    options
    |> connection.open(host: "example.com", port: 443),
  )
  let exchange = {
    use _protocol <- result.try(connection.await_up(conn, timeout))
    client.get(conn, "/", [], timeout)
  }
  let cleanup = connection.terminate(conn)
  use res <- result.try(exchange)
  use _ <- result.try(cleanup)
  Ok(res)
}
```
## TLS is secure by default

The HTTP/2 example sets only the transport, and that is sufficient. Whenever a
connection uses TLS (`connection.Tls`, or `connection.Auto` resolving to TLS),
Gluegun applies a secure baseline: peer and hostname verification, system CA
certificates, TLS 1.2 and 1.3, SNI for DNS hosts, and HTTPS hostname matching.
Values that you set with the `tls.with_*` builders replace individual
defaults.

The default `connection.Auto` transport uses TLS on port 443 and plain TCP on
other ports. Plain TCP does not load TLS trust roots. If you configure TLS
options, Auto uses TLS on every port. A TLS setup failure returns an error;
Gluegun never falls back to plaintext.

For development against a self-signed server, `tls.insecure()` disables
verification and SNI. Do not ship it. The
[TLS guide](https://gluegun.tylerbutler.com/guides/tls/) lists each default
and override.

## Talk over WebSocket

WebSocket brings back HTTP/1.1, because Gun supports WebSocket only over
HTTP/1.1. `websocket.connect` applies your connection options, including TLS
settings, then forces HTTP/1.1 and zero retries. Reconnection cannot restore
an upgrade, so a dropped connection returns `ConnectionDown`.

A reusable `Socket` gives you explicit control of its lifecycle:

```gleam
import gleam/io
import gleam/result
import gluegun/error
import gluegun/message
import gluegun/websocket

pub fn ws_echo() {
  use socket <- result.try(
    websocket.connect(
      host: "localhost",
      port: 8080,
      path: "/echo",
      options: websocket.options(),
    ),
  )

  let exchange = {
    use _ <- result.try(websocket.send_text(socket, "hello"))
    case websocket.receive_app_frame(socket) {
      Ok(message.Text(reply)) -> {
        io.println(reply)
        Ok(Nil)
      }
      Ok(_) -> Error(error.InvalidMessage("expected a text frame"))
      Error(error) -> Error(error)
    }
  }

  let cleanup = websocket.close(socket)
  use _ <- result.try(exchange)
  cleanup
}
```
As with an HTTP connection, the example creates its cleanup before it examines
the result. Call `websocket.close(socket)` from the receiving process, even
after an exchange fails. It releases the Gun process and flushes its queued
messages. It waits for the peer for the socket timeout, or five seconds when
the timeout is `Infinity`, and a timeout or handshake error still tears the
socket down. A second close succeeds after the process exits. In contrast,
`send_close_frame` only sends a frame.

For a short exchange, `with_socket` does this teardown for you. It opens the
socket, runs your callback, then closes the WebSocket and its connection. A
callback error takes precedence over a cleanup error.

```gleam
import gleam/io
import gleam/result
import gluegun/error
import gluegun/message
import gluegun/websocket

pub fn echo_once() {
  use frame <- result.try(
    websocket.with_socket(
      host: "localhost",
      port: 8080,
      path: "/echo",
      options: websocket.options(),
      callback: fn(socket) {
        use _ <- result.try(websocket.send_text(socket, "hello"))
        websocket.receive_app_frame(socket)
      },
    ),
  )

  case frame {
    message.Text(reply) -> {
      io.println(reply)
      Ok(Nil)
    }
    _ -> Error(error.InvalidMessage("expected a text frame"))
  }
}
```
To upgrade a connection that you already opened, call `websocket.upgrade`
with the negotiated protocol and upgrade options, then `await_upgrade`, then
`from_upgrade`. The resulting `Socket` uses the same frame and close
operations.

Keepalive pings are off by default (`infinity()`). For `connect` and
`with_socket`, set `websocket.with_keepalive` on the upgrade options that you
give to `websocket.with_upgrade_options`; that setting overrides
`connection.with_websocket_keepalive`. For a low-level upgrade, set
`connection.with_websocket_keepalive` before `connection.open` instead. Gun
cannot change its connection timer through upgrade options, so
`websocket.upgrade` rejects `websocket.with_keepalive` with `InvalidOptions`,
even for `infinity()`. Keepalive does not change your receive timeout.

See `examples/websocket_echo` for a fuller WebSocket example.

For an OTP actor, use `message.select` to receive source-identified Gun events
and application commands in one selector. Open the connection inside actor
init, and pass each WebSocket envelope to `websocket.record_frame` before
handling it. See the [actor guide](https://gluegun.tylerbutler.com/guides/actors/)
and `examples/websocket_actor`. No caller Erlang FFI is needed.

## Handle errors

Each example above returns a `Result`. Effectful operations return
`Result(_, error.GluegunError)`, and pure builders and accessors return plain
values. Match the variants that are important to your application, and keep a
fallback for unexpected Erlang or decode errors:

```gleam
import gleam/io
import gleam/result
import gluegun/client
import gluegun/connection
import gluegun/error

fn safe_get(conn) {
  use timeout <- result.try(connection.milliseconds(5000))

  case client.get(conn, "/", [], timeout) {
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
Options follow the same rule. A numeric option with an invalid value returns
`InvalidOptions` instead of a clamped value. That is why even a literal
timeout, such as `connection.milliseconds(5000)`, returns a `Result`. The
[error handling guide](https://gluegun.tylerbutler.com/advanced/error-handling/)
lists the accepted ranges.

## Limitations

- Gluegun runs only on the Erlang target, because it wraps Erlang Gun.
- Process ownership matters. Gun sends stream and WebSocket messages to the
  process that owns or awaits the stream, unless request options redirect
  replies.
- `client` helpers collect full response bodies in memory. Use the low-level
  `request` and `message` APIs to stream.
- Gun does not support WebSocket over HTTP/2, so `websocket.upgrade` rejects it.
- The typed TLS options cover a small set at first. Advanced TLS options can
  need future typed additions.
- After cancellation with exhausted finite flow credit, Gun can leave HTTP/1.1
  reads paused. Terminate and replace that connection, which discards its
  other requests. This upstream limitation applies to 1.0; see
  [#78](https://github.com/tylerbutler/gluegun/issues/78) and
  [ninenines/gun#56](https://github.com/ninenines/gun/issues/56).
- Response header strings must be UTF-8. Invalid wire values return
  `DecodeError` instead of invalid Gleam strings or changed bytes.

## Examples

Each directory under `examples/` is a standalone Gleam package for the Erlang
target. They follow the same path as this README, from a first request to a
complete command-line tool:

- `basic_request`: open a connection, send a GET, print the negotiated
  protocol, and collect a text response.
- `json_post`: send a JSON body with headers through the client builder.
- `http2_preferred`: prefer HTTP/2 over TLS and allow HTTP/1.1 fallback.
- `chunked_upload`: start a streamed request with `request.start_stream` and
  send body chunks with `request.data`, `fin.NoFin`, and `fin.Fin`.
- `streaming_download`: process response chunks and trailers as message
  values arrive.
- `websocket_echo`: connect to a local WebSocket echo server and exchange one
  text frame.
- `websocket_actor`: own a WebSocket in an OTP actor and receive frames plus
  application commands.
- `websocket_chat`: use the scoped WebSocket helpers for a text and binary
  conversation.
- `webprobe`: a command-line HTTP diagnostics tool built with `clip`, `argv`,
  `gleescript`, and Gluegun.

To run one:

```sh
cd examples/basic_request
gleam deps download
gleam build
gleam run
```

The networked examples need public endpoints or local servers, so run them by
hand with `gleam run`.

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) explains the build tools, CI checks,
dependency audits, website reference builds, and release process.

## License

MIT
