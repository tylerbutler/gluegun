# http2_preferred

The request stays simple here; the connection changes. This example opens
`https://nghttp2.org/` over TLS and offers HTTP/2 first, with HTTP/1.1 as the
fallback. It prints the protocol that the server selected, sends a GET to
`/httpbin/get`, and prints the response status and the UTF-8 body when one
is available.

## Running

Run these commands from this directory:

```sh
gleam deps download
gleam run
```

## Notes

- `https://nghttp2.org/` is a public HTTP/2 demo service. Treat this example as a manual check, not a CI dependency, because it requires external network and TLS availability.
- `client.get` collects the full response body in memory. Use `gluegun/request` and `gluegun/message` for streaming or advanced flows.
- Gluegun does not parse URLs. Open the connection with a host and port, then request a path. If your input is a full URL, parse it first with `gleam/uri`.
- Gun is Erlang-only, so this example targets Erlang.

## Next

[`chunked_upload`](../chunked_upload/README.md) leaves the high-level client and streams a request body.
