# websocket_echo

A minimal example showing how to use **Gluegun**'s high-level WebSocket `Socket` API to connect to an echo server, send a text frame, and receive the echoed reply.

## Protocol limitations

- **HTTP/2 WebSocket is not supported** by Gun (RFC 8441). `websocket.options()` defaults high-level WebSocket connections to HTTP/1.1, and low-level `websocket.upgrade_with_protocol` rejects HTTP/2 before calling Gun.
- Once an HTTP/1.1 connection is upgraded to WebSocket the connection is
  **exclusively** used for WebSocket frames. You cannot send concurrent HTTP
  requests on the same connection.

## API style

The source example uses `websocket.connect` to create a reusable `Socket`, then
`websocket.send_text`, `websocket.receive_app_frame`, and `websocket.close` for
explicit WebSocket lifecycle steps. For scoped one-shot flows, use
`websocket.with_socket` to run a callback and close the WebSocket and connection
afterward. Low-level `upgrade_with_protocol_and_options`, `send`, and `receive`
remain available for advanced use.

## Usage

This example is intentionally kept as source-level documentation. It is not
a separate Gleam package and is not built by the `just` tasks in the root
`justfile`. To adapt it for your own project:

1. Add `gluegun` to your `gleam.toml` dependencies.
2. Copy `src/websocket_echo.gleam` into your project and adjust as needed.
3. Ensure your target is `erlang` (WebSocket requires the Erlang runtime).

## Running

If you want to run it as a standalone project, initialise a Gleam project,
copy the source file, and add the dependencies to `gleam.toml`:

```toml
[dependencies]
gleam_stdlib = ">= 0.48.0 and < 2.0.0"
gleam_erlang = ">= 1.0.0 and < 2.0.0"
gleam_otp    = ">= 1.0.0 and < 2.0.0"
gun          = ">= 2.1.0 and < 3.0.0"
gluegun      = { path = "../.." }
```

Then:

```sh
gleam run
```

> **Note:** The example targets `ws://localhost:8080/echo`. You need a local
> WebSocket echo server listening on that address. A simple option is
> [websocat](https://github.com/vi/websocat):
>
> ```sh
> websocat -s 8080
> ```
