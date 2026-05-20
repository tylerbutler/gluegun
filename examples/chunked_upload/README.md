# chunked_upload

A buildable low-level request-body streaming example for Gluegun. It opens `http://httpbingo.org`, starts a `POST /post` request with headers only, streams the request body in multiple chunks, waits for the response, collects the response body when needed, prints the final status, and closes the connection.

## Running

Run these commands from this directory:

```sh
gleam deps download
gleam run
```

## Notes

- `http://httpbingo.org/post` is useful for manual demos. Automated tests should use a local deterministic server instead of the public endpoint.
- This example uses `gluegun/request` and `gluegun/message` directly to demonstrate request-body streaming. Use `gluegun/client` for simple full-body requests.
- Gluegun does not parse URLs. Open the connection with a host and port, then request a path.
- Gun is Erlang-only, so this example targets Erlang.
