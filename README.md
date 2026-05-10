# gluegun

[![Package Version](https://img.shields.io/hexpm/v/gluegun)](https://hex.pm/packages/gluegun)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gluegun/)

A Gleam wrapper for the Erlang [Gun](https://ninenines.eu/docs/en/gun/) HTTP client.

Gun is an asynchronous HTTP client supporting HTTP/1.1, HTTP/2, and WebSocket over HTTP/1.1. Because Gun is Erlang-only, gluegun targets the Erlang runtime.

## Installation

```sh
gleam add gluegun
```

## Usage

```gleam
import gluegun

pub fn main() {
  gluegun.name()
  // -> "gluegun"
}
```

### HTTP/2

Use TLS and put `Http2` before `Http1` to prefer HTTP/2 while allowing Gun to
fall back to HTTP/1.1 when needed.

```gleam
import gluegun/client
import gluegun/connection

pub fn get_over_http2() {
  let options =
    connection.connect_options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.with_protocols(protocols: [connection.Http2, connection.Http1])

  let assert Ok(conn) = connection.open("example.com", 443, options)
  let assert Ok(connection.Http2) =
    connection.await_up(conn, connection.Milliseconds(5000))

  client.get(conn, "/", [], connection.Milliseconds(5000))
}
```

gluegun supports normal HTTP/2 request/response streams through Gun's HTTP
message flow. Gun does not support WebSocket over HTTP/2, so gluegun only
supports WebSocket over HTTP/1.1.

## Development

```sh
just deps         # Download dependencies
just build        # Build project
just test         # Run tests
just format       # Format code
just format-check # Check formatting
just check        # Type check
just docs         # Build documentation
just ci           # Run all CI checks
```

## License

MIT
