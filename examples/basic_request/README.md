# basic_request

A buildable Gluegun example that opens `http://example.com/`, negotiates a protocol, makes a GET request, and prints the negotiated protocol, response status, and response body.

## Running

Run these commands from this directory:

```sh
gleam deps download
gleam run
```

## Notes

- `client.get` collects the full response body in memory. Use `gluegun/request` and `gluegun/message` for streaming or advanced flows.
- Gluegun does not parse URLs. Open the connection with a host and port, then request a path. If your input is a full URL, parse it first with `gleam/uri`.
- Gun is Erlang-only, so this example targets Erlang.
