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
    message.await(conn, stream, timeout)

  case response_fin {
    fin.Fin -> <<>>
    fin.NoFin -> {
      let assert Ok(body) = message.await_body(conn, stream, timeout)
      body
    }
  }
}
```

## Consuming response chunks

If you need response chunks or trailers as they arrive, continue awaiting `message.Data` and `message.Trailers` with `message.await` instead of collecting the full body with `message.await_body`.

Streaming APIs are also the right place for cancellation, flow-control updates, and flushing.
