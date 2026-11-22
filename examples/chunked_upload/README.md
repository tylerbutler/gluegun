# chunked_upload

The earlier examples send a complete body. This one produces the body in
pieces with the low-level API. It opens `https://httpbin.org`, starts a
`POST /post` request with headers only, then streams the body in several
chunks. After the last chunk, it waits for the response, collects the body
when there is one, prints the final status, and closes the connection.

## Running

Run these commands from this directory:

```sh
gleam deps download
gleam run
```

## Notes

- `https://httpbin.org/post` is useful for manual demos. Automated tests should use a local deterministic server instead of the public endpoint.
- This example uses `gluegun/request` and `gluegun/message` directly to demonstrate request-body streaming. Use `gluegun/client` for simple full-body requests.
- Gluegun does not parse URLs. Open the connection with a host and port, then request a path. If your input is a full URL, parse it first with `gleam/uri`.
- Gun is Erlang-only, so this example targets Erlang.

## Next

[`streaming_download`](../streaming_download/README.md) streams in the other direction.
