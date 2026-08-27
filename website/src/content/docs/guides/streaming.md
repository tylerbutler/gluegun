---
title: Streaming
description: Send chunked request bodies and read asynchronous response messages.
---

Use `gluegun/request` when you make the request body in chunks.

Start with `request.start_stream`. Send zero or more chunks with `fin.NoFin`. Complete the body with `fin.Fin`.

```gleam
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/message
import gluegun/request
import gleam/result

pub fn upload_chunks(conn) {
  let timeout = connection.Milliseconds(5000)

  use stream <- result.try(
    request.start_stream(
      conn,
      request.Post,
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

fn await_final_response(conn, stream, timeout) {
  case message.await(conn, stream, timeout) {
    Ok(message.Inform(_status, _headers)) ->
      await_final_response(conn, stream, timeout)
    other -> other
  }
}
```

## Message sequence

Gun sends stream messages in a defined order. A usual HTTP request stream gives:

1. Zero or more `message.Inform(status, headers)` — 1xx informational responses.
2. Exactly one `message.Response(fin, status, headers)` — the final status line and headers. If `fin` is `Fin`, the body is empty and no more messages come (except possible trailers).
3. Zero or more `message.Data(fin, bytes)` — body chunks. The last chunk has `fin.Fin`.
4. Zero or one `message.Trailers(headers)` — HTTP/1.1 trailers or HTTP/2 trailer frames.

HTTP/2 server push comes as `message.Push(stream, …)`. It holds a new stream. You can wait for that stream or cancel it. Protocol upgrade flows give `message.Upgrade(...)`. After a successful WebSocket upgrade, frames come as `message.WebSocket(frame)`. The high-level `client` functions reject `Push`, `Upgrade`, and `WebSocket` with `InvalidMessage`. Use the low-level loop for these messages.

## Read response chunks

To get response chunks or trailers as they arrive, continue to call `message.await` for `message.Data` and `message.Trailers`. Do not collect the full body with `message.await_body`.

`message.await_body` collects all body chunks into one `BitArray` in memory. Call it only after you receive the `Response` message (for example, from a previous `message.await`). For very large responses, or responses without a known size, write your own loop with `message.await`. Then you can apply backpressure or send the body to a different location.

## Stream control

The streaming APIs also control the request:

- Use `request.cancel(conn, stream)` to cancel a request stream.
- Use `request.update_flow(conn, stream, increment)` when your application controls the flow-control allowance directly. The increment must be positive.
- Use `request.flush(conn)` to flush the queued Gun messages for a connection.

See the [request reference](/reference/gluegun-request/) and [message reference](/reference/gluegun-message/) for the full streaming API.
