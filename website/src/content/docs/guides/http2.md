---
title: HTTP/2
description: Prefer HTTP/2 while keeping HTTP/1.1 fallback explicit.
---

Use TLS and put `Http2` before `Http1` to prefer HTTP/2 while allowing Gun to fall back to HTTP/1.1 when needed.

## How fallback works

Protocol selection happens through TLS ALPN (Application-Layer Protocol Negotiation). When you list `[Http2, Http1]`, Gun advertises both `h2` and `http/1.1` in the TLS ClientHello. The server picks one and the chosen protocol is returned by `connection.await_up`. If the server only advertises HTTP/1.1, Gun negotiates HTTP/1.1 and `await_up` returns `Http1`.

Plain TCP (`connection.Tcp`) does not negotiate; Gun uses the first protocol in the list.

```gleam
import gleam/result
import gluegun/client
import gluegun/connection

pub fn get_over_http2() {
  let options =
    connection.options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.with_protocols(protocols: [connection.Http2, connection.Http1])

  use conn <- result.try(
    options
    |> connection.open(host: "example.com", port: 443),
  )
  use protocol <- result.try(
    connection.await_up(conn, connection.Milliseconds(5000)),
  )

  case protocol {
    connection.Http2 -> Nil
    connection.Http1 -> Nil
  }

  client.get(conn, "/", [], connection.Milliseconds(5000))
}
```

## WebSocket note

WebSocket support is HTTP/1.1 only. Use HTTP/2 for regular HTTP requests and keep WebSocket connections on HTTP/1.1. Calling `websocket.upgrade_with_protocol` on an HTTP/2 connection returns `UnsupportedFeature` before reaching Gun.

See the [connection reference](/reference/gluegun-connection/) for the complete connection option API.
