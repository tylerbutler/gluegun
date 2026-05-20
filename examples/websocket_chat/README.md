# websocket_chat

A buildable scoped WebSocket lifecycle example for Gluegun.

The example opens `ws://localhost:8080/chat` with `websocket.with_socket`,
sends one text frame and one binary frame, receives one application frame after
each send, prints frame summaries, and lets the scoped helper close the
WebSocket and connection.

## Running

Start a local WebSocket server that accepts `ws://localhost:8080/chat` and
echoes text and binary frames. Then run:

```sh
cd examples/websocket_chat
gleam deps download
gleam run
```

Do not run this example unless a suitable local server is available.

## Protocol limitations

Gun supports WebSocket over HTTP/1.1 only. `websocket.options()` constrains the
connection to HTTP/1.1 for the WebSocket upgrade.
