---
title: Streaming
description: Send chunked request bodies and consume asynchronous response messages.
---

Use `gluegun/request` when the request body is produced in chunks.

Start with `request.start_stream`, send zero or more chunks with `fin.NoFin`, and complete the body with `fin.Fin`.

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

## Message sequencing

Gun delivers stream messages in a defined order. A typical HTTP request stream produces:

1. Zero or more `message.Inform(status, headers)` — 1xx informational responses.
2. Exactly one `message.Response(fin, status, headers)` — the final status line and headers. If `fin` is `Fin`, the body is empty and no further messages arrive (other than optional trailers).
3. Zero or more `message.Data(fin, bytes)` — body chunks. The last chunk carries `fin.Fin`.
4. Optionally one `message.Trailers(headers)` — HTTP/1.1 trailers or HTTP/2 trailer frames.

HTTP/2 server push appears as `message.Push(stream, …)` carrying a new stream you can await or cancel. Protocol upgrade flows produce `message.Upgrade(...)`. After a successful WebSocket upgrade, frames are delivered as `message.WebSocket(frame)`. The high-level `client` helpers reject `Push`, `Upgrade`, and `WebSocket` with `InvalidMessage` — handle them with the low-level loop instead.

## Consuming response chunks

If you need response chunks or trailers as they arrive, continue awaiting `message.Data` and `message.Trailers` with `message.await` instead of collecting the full body with `message.await_body`.

`message.await_body` is a convenience that drains body chunks into a single `BitArray` in memory. It must be called *after* the `Response` message has been received (e.g. via a prior `message.await`). For very large or unbounded responses, write your own loop using `message.await` so you can apply backpressure or stream the body elsewhere.

## Stream control

Streaming APIs are also the right place for request control:

- Use `request.cancel(conn, stream)` to cancel a request stream.
- Use `request.update_flow(conn, stream, increment)` when your application manages flow-control allowance directly. The increment must be positive.
- Use `request.flush(conn)` to flush queued Gun messages for a connection.

See the [request reference](/reference/gluegun-request/) and [message reference](/reference/gluegun-message/) for the complete streaming API.
