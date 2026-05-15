---
title: Streaming
description: Send chunked request bodies and consume asynchronous response messages.
---

Use `gluegun/request` when the request body is produced in chunks.

Start with `request.headers`, send zero or more chunks with `fin.NoFin`, and complete the body with `fin.Fin`.

```gleam
import gluegun/connection
import gluegun/fin
import gluegun/message
import gluegun/request

pub fn upload_chunks(conn) {
  let timeout = connection.Milliseconds(5000)

  let assert Ok(stream) =
    request.headers(
      conn,
      request.Post,
      "/upload",
      [#("content-type", "text/plain")],
      request.options(),
    )

  let assert Ok(Nil) = request.data(conn, stream, fin.NoFin, <<"first ":utf8>>)
  let assert Ok(Nil) = request.data(conn, stream, fin.Fin, <<"last":utf8>>)

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

## Consuming response chunks

If you need response chunks or trailers as they arrive, continue awaiting `message.Data` and `message.Trailers` with `message.await` instead of collecting the full body with `message.await_body`.

Servers may send one or more `message.Inform` values before the final `message.Response`. Skip or record those informational responses before collecting the response body. HTTP/2 servers can also send `message.Push` values, and upgrade flows can produce `message.Upgrade` or `message.WebSocket` values that the high-level client helpers intentionally reject.

## Stream control

Streaming APIs are also the right place for request control:

- Use `request.cancel(conn, stream)` to cancel a request stream.
- Use `request.update_flow(conn, stream, increment)` when your application manages flow-control allowance directly. The increment must be positive.
- Use `request.flush(conn)` to flush queued Gun messages for a connection.

See the [request reference](/reference/gluegun-request/) and [message reference](/reference/gluegun-message/) for the complete streaming API.
