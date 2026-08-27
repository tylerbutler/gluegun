---
title: HTTP/2
description: Select HTTP/2 first and keep the HTTP/1.1 fallback explicit.
---

Use TLS and put `Http2` before `Http1`. Gun then selects HTTP/2 when possible and falls back to HTTP/1.1 when necessary.

## How fallback works

TLS ALPN (Application-Layer Protocol Negotiation) selects the protocol. When you list `[Http2, Http1]`, Gun advertises `h2` and `http/1.1` in the TLS ClientHello. The server selects one. `connection.await_up` returns the selected protocol. If the server advertises only HTTP/1.1, Gun negotiates HTTP/1.1 and `await_up` returns `Http1`.

Plain TCP (`connection.Tcp`) does not negotiate. Gun uses the first protocol in the list.

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

WebSocket works only on HTTP/1.1. Use HTTP/2 for usual HTTP requests. Keep WebSocket connections on HTTP/1.1. If you call `websocket.upgrade_with_protocol` on an HTTP/2 connection, it returns `UnsupportedFeature` and does not call Gun.

See the [connection reference](/reference/gluegun-connection/) for the full connection option API.
