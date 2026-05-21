# websocket_echo

A buildable Gluegun example package that connects to a local WebSocket echo
server, sends a text frame, receives the echoed reply, and closes the socket.

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

The source example uses `websocket.connect` to create a reusable `Socket`, then
`websocket.send_text`, `websocket.receive_app_frame`, and `websocket.send_close_frame` for
explicit WebSocket lifecycle steps. For scoped one-shot flows, use
`websocket.with_socket` to run a callback and close the WebSocket and connection
afterward. Low-level `upgrade_with_protocol_and_options`, `send`, and `receive`
remain available for advanced use.
