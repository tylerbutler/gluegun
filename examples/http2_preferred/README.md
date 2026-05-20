# http2_preferred

A buildable Gluegun example that opens `https://nghttp2.org/`, prefers HTTP/2 over TLS with HTTP/1.1 fallback, prints the negotiated protocol, makes a GET request, and prints the response status and UTF-8 body when available.

## Running

Run these commands from this directory:

```sh
gleam deps download
gleam run
```

## Notes

- `https://nghttp2.org/` is a public HTTP/2 demo service. Treat this example as a manual check, not a CI dependency, because it requires external network and TLS availability.
- `client.get` collects the full response body in memory. Use `gluegun/request` and `gluegun/message` for streaming or advanced flows.
- Gluegun does not parse URLs. Open the connection with a host and port, then request a path.
- Gun is Erlang-only, so this example targets Erlang.
