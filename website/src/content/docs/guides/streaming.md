---
title: Streaming
description: Send chunked request bodies and read asynchronous response messages.
---

Use `gluegun/request` when you make the request body in chunks.

Start with `request.start_stream`. Send zero or more chunks with `fin.NoFin`. Complete the body with `fin.Fin`.

```gleam
import gleam/http
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/message
import gluegun/request
import gleam/result

pub fn upload_chunks(conn) {
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
- Use `request.update_flow(conn, stream, increment)` to add data-message credit. The increment must be positive.
- Use `request.flush(conn)` to remove Gun messages queued at the time of the call. Cancellation can still produce late arrivals.
- Use `connection.terminate(conn)` for terminal cleanup: force process exit, wait, and flush its Gun messages from this receiver.

## Finite response credit

Set credit before you start the request:

```gleam
import gleam/http
use options <- result.try(
  request.options() |> request.with_initial_flow(credit: 1),
)
use stream <- result.try(
  request.request(conn, http.Get, path, [], <<>>, options),
)
```

Both `request.request` and `request.start_stream` pass this option to Gun. Credit must be positive. Without a setting, Gun keeps its unlimited default. Adding credit after an unlimited start cannot establish backpressure.

Use finite credit with your `message.await` loop. `message.await_body` and the high-level `client` collectors do not replenish credit and can time out after they consume it.

With Gun's default data handler, credit counts `message.Data` messages, not bytes. Headers do not consume credit. You can inspect status and `Content-Length` before you retain body data, although the first body message can already be in your mailbox. Reject non-success statuses and an oversized length, then cancel and terminate the connection.

For an accepted response, count `bit_array.byte_size(data)` for each `message.Data` before you retain, print, or write it. Reject a chunk when its size exceeds the remaining byte allowance. This check must include the final `fin.Fin` chunk. It also applies to chunked and close-delimited responses, which do not need a `Content-Length`. After processing each non-final chunk, call `request.update_flow(conn, stream, 1)`.

Flow credit cannot impose a strict allocation cap:

- Gun can split a large HTTP chunk over socket reads, or combine small HTTP chunks into a data message. HTTP chunk boundaries do not define message size.
- Gun can parse several HTTP/2 frames from a socket read before it stops stream-window updates. Data already inside the HTTP/2 window can still arrive.
- OTP and the operating system hold socket buffers. Gun also holds parser state and buffered bytes. Gluegun does not set a maximum size for these allocations or for one `BitArray`.

The local acceptance tests send a 1 MiB HTTP chunk and 4096 small chunks. They confirm that HTTP/1.1 stops delivery when the initial credit runs out and resumes after `update_flow`. A local HTTP/2 peer fills Gun's advertised stream byte window, checks that finite credit prevents stream `WINDOW_UPDATE`, then confirms that replenishing data-message credit resumes delivery. It also checks the final chunk's cumulative byte count and termination cleanup with a real queued server push. The byte-policy tests reject bodies from both chunked and close-delimited responses. The caller owns the byte limit and any archive processing.

## Connection setup time limits

```gleam
use stage_timeout <- result.try(connection.milliseconds(1000))
use retries <- result.try(connection.retry_count(0))

let connect_options =
  connection.options()
  |> connection.with_transport(connection.Tls)
  |> connection.with_address_family(connection.Ipv6)
  |> connection.with_retry(retries)
  |> connection.with_domain_lookup_timeout(stage_timeout)
  |> connection.with_connect_timeout(stage_timeout)
  |> connection.with_tls_handshake_timeout(stage_timeout)
```

Reuse the address family that your command selected. `Ipv4` uses only IPv4 addresses; `Ipv6` uses only IPv6 addresses. Gun uses this selection for DNS lookup and TCP connection, including the TCP socket below TLS. It does not switch families on failure. Keep the DNS hostname as `open`'s host to preserve hostname verification and SNI. These controls do not disable peer verification or system CA roots.

Gun 2.1 and 2.2 split setup into three stages on OTP 27:

| Setting | Coverage per attempt | Default |
|---|---|---|
| `with_domain_lookup_timeout` | Gun's OTP address lookup timer | Unlimited |
| `with_connect_timeout` | Socket connection across addresses returned by lookup | 5000 ms in Gluegun |
| `with_tls_handshake_timeout` | TLS handshake after TCP connection | Unlimited |

`connect_timeout` does not cover DNS or TLS. Resolver behavior depends on OTP and the host resolver configuration; stage timers do not replace the caller's total deadline. `retry_count(0)` disables retries. The default is zero retries; Gun uses a separate five-second retry delay. `with_retry` accepts a `RetryCount`, not a timeout or retry duration.

## Total deadline and cleanup

Before `open`, record `deadline = monotonic_now_ms + budget_ms`. Before each `await_up` or `message.await`, compute `remaining = deadline - monotonic_now_ms`. If it is non-positive, stop. Otherwise pass `connection.milliseconds(remaining)`. Recompute after informational responses and each data chunk; a fresh full timeout for each receive would let a dribbling peer extend the operation.

Use Erlang's `erlang:monotonic_time(millisecond)` for the clock. Include time spent processing chunks in the budget and check the deadline before further credit. An `await` timeout only stops that receive; it does not stop Gun. On expiry or rejection, cancel the stream if one exists, then call `connection.terminate` even if cancellation fails. Report cleanup errors as well as the original failure.

`terminate` can interrupt Gun during DNS lookup, socket connect, or TLS handshake. It sends a kill signal, waits for the process monitor's exit notification, then flushes that connection's Gun messages. Call it from the process that receives the messages, with no external forwarder still sending them. Other receiving processes must drain their own mailboxes. `request.flush` alone only clears the current queue.

The buildable [`examples/streaming_download`](https://github.com/tylerbutler/gluegun/tree/main/examples/streaming_download) demonstrates finite credit, header checks, actual-byte checks, stage timeouts, a monotonic total deadline, and terminal cleanup.

See the [request reference](/reference/gluegun-request/) and [message reference](/reference/gluegun-message/) for the full streaming API.
