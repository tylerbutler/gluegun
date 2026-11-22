# websocket_echo

The first WebSocket example. It connects to a local echo server, sends one
text frame, receives the echoed reply, and closes the socket. Unlike the HTTP
examples, it needs a server that you start yourself.

## Running

Start a local WebSocket echo server:

```sh
websocat -s 8080
```

In another terminal, run the example:

```sh
cd examples/websocket_echo
gleam deps download
gleam run
```

The example targets `ws://localhost:8080/echo`.

## Protocol limitations

- WebSocket support is HTTP/1.1 only. Gun does not support WebSocket over HTTP/2
  (RFC 8441).
- Once an HTTP/1.1 connection is upgraded, the connection is exclusively used
  for WebSocket frames. You cannot send concurrent HTTP requests on it.

## API style

The example manages each lifecycle step itself. `websocket.connect` creates a
reusable `Socket`, then `websocket.send_text` and `websocket.receive_app_frame`
exchange one message. `websocket.close` runs last, even after a failed
exchange. It waits for the peer within the socket timeout, then releases the
Gun process even on a handshake error. In contrast, `send_close_frame` only
sends a frame.

Two other entry points lead to the same `Socket`. For a scoped one-shot flow,
`websocket.with_socket` runs a callback, then closes the WebSocket and the
connection. For a connection that you already opened, call `upgrade` with the
negotiated protocol, then `await_upgrade` and `from_upgrade`. The resulting
`Socket` uses the same send, receive, and close functions.

## Next

[`websocket_chat`](../websocket_chat/README.md) uses `with_socket` so that the
helper handles the close.
