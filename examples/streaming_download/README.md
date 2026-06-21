# streaming_download

A buildable low-level response streaming example for Gluegun. It opens `https://httpbin.org`, sends `GET /stream/5`, waits for the initial response, then consumes response data messages as they arrive and prints each chunk size before closing the connection.

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
