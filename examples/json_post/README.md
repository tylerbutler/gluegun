# json_post

This example builds on `basic_request` by sending data. It opens
`http://httpbingo.org`, waits for protocol negotiation, and sends a JSON
`POST` to `/post` with the `client` builder. It prints the negotiated
protocol, the response status, the number of response headers, and the UTF-8
response body.

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

## Next

[`http2_preferred`](../http2_preferred/README.md) changes the protocol instead of the request.
