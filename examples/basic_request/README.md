# basic_request

The first Gluegun example: one connection and one request. It opens
`http://example.com/`, waits for Gun to negotiate a protocol, sends a GET, and
prints the negotiated protocol, the response status, and the response body.
The other examples start from this shape.

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

## Next

[`json_post`](../json_post/README.md) adds a request body and headers.
