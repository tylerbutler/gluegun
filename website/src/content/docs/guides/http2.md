---
title: HTTP/2
description: Prefer HTTP/2 while keeping HTTP/1.1 fallback explicit.
---

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

## WebSocket note

WebSocket support is HTTP/1.1 only. Use HTTP/2 for regular HTTP requests and keep WebSocket connections on HTTP/1.1.

See the [connection reference](/reference/gluegun-connection/) for the complete connection option API.
