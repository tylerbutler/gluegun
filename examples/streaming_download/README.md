# streaming_download

`chunked_upload` streams a request; this example streams a response. It opens
`https://httpbin.org` and sends `GET /stream/5`. After the response headers
arrive, it reads each data message as it arrives and prints its size, then
closes the connection.

## Running

Run these commands from this directory:

```sh
gleam deps download
gleam run
```

## Notes

- `https://httpbin.org/stream/5` is useful for manual demos. Automated tests should use a local deterministic streaming handler instead of the public endpoint.
- This example uses `gluegun/request` and `gluegun/message` directly to demonstrate response-body streaming. Use `gluegun/client` for simple full-body requests.
- Gluegun does not parse URLs. Open the connection with a host and port, then request a path. If your input is a full URL, parse it first with `gleam/uri`.
- Gun is Erlang-only, so this example targets Erlang.

## Next

[`websocket_echo`](../websocket_echo/README.md) moves from HTTP streams to WebSocket frames.
