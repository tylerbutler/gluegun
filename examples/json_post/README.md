# json_post

A buildable Gluegun example that opens `http://httpbingo.org`, negotiates a protocol, sends a JSON `POST` request to `/post`, and prints the negotiated protocol, response status, response header count, and UTF-8 response body.

## Running

Run these commands from this directory:

```sh
gleam deps download
gleam run
```

## Notes

- `http://httpbingo.org/post` is useful for manual demos and should not be used by automated tests.
- `client.send` collects the full response body in memory. Use `gluegun/request` and `gluegun/message` for streaming or advanced flows.
- Gluegun does not parse URLs. Open the connection with a host and port, then request a path. If your input is a full URL, parse it first with `gleam/uri`.
- Gun is Erlang-only, so this example targets Erlang.
