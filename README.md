# Gluegun

[![Docs](https://img.shields.io/badge/docs-gluegun.tylerbutler.com-ffaff3)](https://gluegun.tylerbutler.com/)
[![CI](https://github.com/tylerbutler/gluegun/actions/workflows/ci.yml/badge.svg)](https://github.com/tylerbutler/gluegun/actions/workflows/ci.yml)

A Gleam wrapper for the Erlang [Gun](https://ninenines.eu/docs/en/gun/) HTTP client.

Gun is an asynchronous HTTP client supporting HTTP/1.1, HTTP/2, and WebSocket over HTTP/1.1. Gluegun gives Gleam callers typed connection, request, response, message, and WebSocket helpers while preserving access to Gun's stream-oriented model. Because Gun is Erlang-only, Gluegun targets the Erlang runtime.

## Installation

Gluegun is distributed as a Git dependency until `1.0`. Add it to your
`gleam.toml` instead of using `gleam add`:

```toml
[dependencies]
gluegun = { git = "https://github.com/tylerbutler/gluegun.git", ref = "main" }
```

For reproducible builds, replace `main` with a release tag or commit SHA.

## Compatibility

- Erlang target only; Gluegun wraps the Erlang Gun client and does not support the JavaScript target.
- Supports Gleam `>= 1.7.0` and Gun `>= 2.1.0 and < 3.0.0`.

## Security

Gluegun is **secure by default** for TLS. Whenever a connection uses TLS
(`connection.Tls`, or `connection.Auto` resolving to TLS), Gluegun applies a
secure baseline at connection time: peer and hostname verification, system CA
certificates, TLS 1.2/1.3, SNI for DNS hosts, and HTTPS hostname matching.

The minimal HTTPS setup is just `connection.options() |> connection.with_transport(transport: connection.Tls)`. Override individual fields with the `tls.with_*` builders; user-supplied values always win.

For development against self-signed endpoints, use `tls.insecure()`, which disables verification and SNI. Do not ship it.

See the [TLS guide](https://gluegun.tylerbutler.com/guides/tls/) for the canonical default list, full details, and overrides.

## Basic GET

Open a Gun connection, wait for it to be ready, send a GET, and collect the full response in memory.

```gleam
import gleam/int
import gleam/io
import gleam/result
import gluegun/client
import gluegun/connection
import gluegun/request
import gluegun/response

pub fn main() {
  use timeout <- result.try(connection.milliseconds(5000))

  use conn <- result.try(
    connection.options()
    |> connection.open(host: "example.com", port: 80),
  )
  use _protocol <- result.try(connection.await_up(conn, timeout))

  use res <- result.try(
    client.new(request.Get, "/")
    |> client.with_timeout(timeout: timeout)
    |> client.send(connection: conn),
  )

  io.println("status: " <> int.to_string(response.status(res)))

  case response.body_text(res) {
    Ok(text) -> io.println(text)
    Error(_) -> io.println("response body was not UTF-8")
  }

  connection.close(conn)
}
```

## One-shot helper on an existing connection

`gluegun/client` helpers are one-shot per request: they send one request on an existing connection and collect that response. Gluegun does not parse URLs; pass the host and port to `connection.open`, then pass a path to request helpers. If your input is a full URL, parse it first with the standard `gleam/uri` module and pass the parsed `host`, `port`, `path`, and `query` pieces into Gluegun.

```gleam
import gluegun/client
import gluegun/request

fn fetch_json(conn, path, timeout) {
  client.new(request.Get, path)
  |> client.with_header(name: "accept", value: "application/json")
  |> client.with_timeout(timeout: timeout)
  |> client.send(connection: conn)
}
```

When collection fails, `client` helpers attempt to cancel that stream and drain its queued messages. They return the original error and keep other streams and the shared connection open. Cleanup failures produce a warning. Cancellation is asynchronous, so messages in transit can arrive after the drain. The high-level helpers do not return the failed stream handle; use the low-level API in a separate receiving process if you need strict mailbox isolation.

## Streaming a request body

Use `gluegun/request` when the request body is produced in chunks. Start with `request.start_stream`, send zero or more chunks with `fin.NoFin`, and complete the body with `fin.Fin`. Response headers and body are separate asynchronous Gun stream messages; use `gluegun/message` helpers or your own receive loop for advanced flows.

```gleam
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/message
import gluegun/request
import gleam/result

pub fn upload_chunks(conn) {
  use timeout <- result.try(connection.milliseconds(5000))

  use stream <- result.try(
    request.start_stream(
      conn,
      request.Post,
      "/upload",
      [#("content-type", "text/plain")],
      request.options(),
    ),
  )

  use _ <- result.try(request.data(conn, stream, fin.NoFin, <<"first ":utf8>>))
  use _ <- result.try(request.data(conn, stream, fin.Fin, <<"last":utf8>>))

  // Await response headers, then consume the response body.
  use response <- result.try(message.await(conn, stream, timeout))

  case response {
    message.Response(fin.NoFin, _status, _headers) ->
      message.await_body(conn, stream, timeout)
    message.Response(fin.Fin, _status, _headers) -> Ok(<<>>)
    _ -> Error(error.InvalidMessage("expected a final response message"))
  }
}
```

If you need response chunks or trailers as they arrive, continue awaiting
`message.Data` and `message.Trailers` with `message.await` instead of collecting
the full body with `message.await_body`.

For bounded response streaming, set `request.with_initial_flow(options, 1)`
before you send the request. Check status and `Content-Length`, then count each
`message.Data` chunk's bytes before retaining it. Grant one more data-message
credit with `request.update_flow(conn, stream, 1)` after each check. Credit is
not a byte or allocation limit.

Use `connection.with_address_family` to select IPv4 or IPv6 without fallback.
Set `with_domain_lookup_timeout`, `with_connect_timeout`, and
`with_tls_handshake_timeout` to bound separate setup stages. Construct a
`RetryCount` with `connection.retry_count(0)` and pass it to `with_retry` to
disable retries. These settings preserve the TLS verification defaults.
Use a monotonic total deadline across setup and response receives.
`connection.terminate` stops a stalled connection, waits for exit, and flushes
its messages from the caller's mailbox.

See `examples/streaming_download` and the
[streaming guide](https://gluegun.tylerbutler.com/guides/streaming/) for a
bounded receive loop and the limits of Gun flow control.

## Prefer HTTP/2

Use TLS and put `Http2` before `Http1` to prefer HTTP/2 while allowing Gun to fall back to HTTP/1.1 when needed.

```gleam
import gleam/result
import gluegun/client
import gluegun/connection

pub fn get_over_http2() {
  let options =
    connection.options()
    |> connection.with_transport(transport: connection.Tls)
    |> connection.with_protocols(protocols: [connection.Http2, connection.Http1])

  use conn <- result.try(
    options
    |> connection.open(host: "example.com", port: 443),
  )
  use timeout <- result.try(connection.milliseconds(5000))
  use protocol <- result.try(connection.await_up(conn, timeout))

  case protocol {
    connection.Http2 -> Nil
    connection.Http1 -> Nil
  }

  client.get(conn, "/", [], timeout)
}
```

## WebSocket echo

Gun supports WebSocket over HTTP/1.1 only. Gluegun's high-level WebSocket options default to HTTP/1.1, and the low-level `upgrade_with_protocol` helpers reject HTTP/2 before calling Gun.

Use the reusable `Socket` API when you want explicit lifecycle control.

```gleam
import gleam/io
import gleam/result
import gluegun/error
import gluegun/message
import gluegun/websocket

pub fn ws_echo() {
  use socket <- result.try(
    websocket.connect(
      host: "localhost",
      port: 8080,
      path: "/echo",
      options: websocket.options(),
    ),
  )

  let exchange = {
    use _ <- result.try(websocket.send_text(socket, "hello"))
    case websocket.receive_app_frame(socket) {
      Ok(message.Text(reply)) -> {
        io.println(reply)
        Ok(Nil)
      }
      Ok(_) -> Error(error.InvalidMessage("expected a text frame"))
      Error(error) -> Error(error)
    }
  }

  let cleanup = websocket.close(socket)
  use _ <- result.try(exchange)
  cleanup
}
```

Call `websocket.close(socket)` from the receiver to release the Gun process and flush its queued messages, including after an exchange fails. It waits for the peer within the socket timeout, or five seconds for `Infinity`. A timeout or handshake error still triggers teardown. Repeated close succeeds after the process exits. `send_close_frame` only sends a frame.

For shorter one-shot flows, `with_socket` opens the socket, runs a callback, then closes the WebSocket and connection.

```gleam
import gleam/io
import gleam/result
import gluegun/error
import gluegun/message
import gluegun/websocket

pub fn echo_once() {
  use frame <- result.try(
    websocket.with_socket(
      host: "localhost",
      port: 8080,
      path: "/echo",
      options: websocket.options(),
      callback: fn(socket) {
        use _ <- result.try(websocket.send_text(socket, "hello"))
        websocket.receive_app_frame(socket)
      },
    ),
  )

  case frame {
    message.Text(reply) -> {
      io.println(reply)
      Ok(Nil)
    }
    _ -> Error(error.InvalidMessage("expected a text frame"))
  }
}
```

`Socket` is reusable and you control its lifecycle. `with_socket` calls the same teardown path and gives callback errors precedence over cleanup errors. Low-level `upgrade_with_protocol_and_options`, `send`, and `receive` remain available for advanced flows. The root facade provides `websocket_connect`, `websocket_send_text`, `websocket_receive_app_frame`, and `websocket_close` for the common path.

See `examples/websocket_echo` for a fuller WebSocket example.

## Error handling

Effectful operations return `Result(_, error.GluegunError)`. Pattern match on variants that matter to your application and keep a fallback for unexpected Erlang or decode errors. Pure builders and accessors return plain values.

```gleam
import gleam/io
import gleam/result
import gluegun/client
import gluegun/connection
import gluegun/error

fn safe_get(conn) {
  use timeout <- result.try(connection.milliseconds(5000))

  case client.get(conn, "/", [], timeout) {
    Ok(response) -> Ok(response)
    Error(error.Timeout) -> {
      io.println("request timed out")
      Error(error.Timeout)
    }
    Error(error.ConnectionDown(reason)) -> {
      io.println("connection down: " <> reason)
      Error(error.ConnectionDown(reason))
    }
    Error(other) -> {
      io.println("request failed")
      Error(other)
    }
  }
}
```

## Limitations

- Erlang target only. Gluegun wraps Erlang Gun and is not available on the JavaScript target.
- Gun process ownership matters. Requests and WebSocket frames are asynchronous messages sent to the process that owns or awaits the Gun stream unless request options redirect replies.
- `client` helpers collect full response bodies in memory. Use low-level `request` and `message` APIs for streaming or advanced Gun flows.
- WebSocket over HTTP/2 is unsupported by Gun. Gluegun rejects it in `websocket.upgrade_with_protocol`.
- TLS option surface is intentionally small at first. Advanced TLS options may require future typed additions.

## Examples

Examples under `examples/` are standalone Erlang-target Gleam packages. To run one:

```sh
cd examples/basic_request
gleam deps download
gleam build
gleam run
```

Available examples:

- `basic_request`: open a connection, send a GET, print negotiated protocol, collect text response.
- `json_post`: send JSON request body with headers using high-level client builder.
- `http2_preferred`: prefer HTTP/2 over TLS while allowing HTTP/1.1 fallback.
- `chunked_upload`: stream request body with `request.headers`, `request.data`, `fin.NoFin`, `fin.Fin`.
- `streaming_download`: process response chunks and trailers as low-level message values arrive.
- `websocket_echo`: connect to local WebSocket echo server and exchange one text frame.
- `websocket_chat`: use scoped WebSocket lifecycle helpers for text and binary frame conversation.
- `webprobe`: standalone CLI demo using `clip` and `argv` for argument parsing, `gleescript` for escript packaging, and Gluegun for HTTP diagnostics.

Root maintenance commands cover all standalone example packages:

```sh
just examples-deps
just examples-format-check
just examples-build
```

Networked examples and WebSocket examples are intended for manual `gleam run` because they depend on public endpoints or local servers.

## Development

```sh
just deps         # Download dependencies
just build        # Build project
just test         # Run tests
just format       # Format src/ and test/
just format-check # Check formatting
just check        # Type check
just docs         # Build documentation
just ci           # Run all CI checks
just main         # Run CI checks and build docs
just td           # Validate the Trellis workspace
```

Add an unreleased change with:

```sh
just change --kind Added --body "Describe the change"
```

Preview the next release with `just changelog-preview`. Trellis creates release
pull requests from pending fragments on `main`. Merge `release/pending` to create
an exact `v{version}` tag and a GitHub release. Tag pushes run CI. Both candidate
and stable releases are Git-only: Hex publication is disabled in the Trellis
configuration and there is no Hex publish job.

### Website reference builds

Commit the generated API pages under `website/src/content/docs/reference/`
and `website/reference-state.json` with changes to source files, `gleam.toml`,
`manifest.toml`, the reference generator, or `.tool-versions`.

Install the tools listed in `.tool-versions` and enable Corepack for the pnpm
version in `website/package.json`. Reference generation requires Gleam, Erlang,
and rebar3. Use these commands from the repository root:

```sh
just site-deps             # Install website dependencies
just site-reference        # Build current Gleam metadata and regenerate pages
just site-reference-check  # Compare committed pages with current metadata
just site-check            # Check freshness and Astro content
just site-build            # Check freshness and build website/dist
just site-dev              # Check freshness and start the dev server
just site-preview          # Check freshness and serve the last site build
```

`just site-reference` uses `website/scripts/generate-reference.mjs` to render
`build/dev/docs/gluegun/package-interface.json`. Run it after you edit source
documentation or a public API, then commit its output. It also records hashes
of the source inputs and reference pages. Do not edit generated pages or the
state record by hand. Repeat generation after a merge that changes these inputs.
When a dev server is running, regenerate references after source edits.

From `website/`, use `pnpm generate:reference` to regenerate or
`pnpm check:reference` to compare committed pages with fresh metadata.
The comparison does not change committed pages. CI runs this comparison and
the reference tests before it checks and builds the website.

Cloudflare Workers Builds uses `website/` as the build root, runs `pnpm build`,
and deploys the static assets in `dist`. See [website deployment](website/README.md)
for the build and preview configuration.
Production and deploy-preview builds need Node and pnpm only. The build checks
the committed source and page hashes before Astro runs and stops if output is
stale or missing. Local `astro`, `build`, `check:astro`, `dev`, `start`, and `preview`
scripts use the same check. Keep Cloudflare's build watch paths at `*` so source,
package manifests, and build configuration trigger production and preview builds.
Run `just site-build`
before `just site-preview` to serve a current build.

### Release candidates

Run the **Trellis Release** workflow manually on `main` to change release mode:

| Action | `pre` input | `version` input |
| --- | --- | --- |
| Start a candidate cycle | `rc` | Target stable version, for example `1.0.0` |
| Prepare the next candidate | `rc` | Leave empty |
| Promote the current candidate to stable | `none` | Leave empty |
| Prepare a normal stable release | Leave empty | Leave empty, or set a target version |

A new cycle starts at `rc.0`. Merge each candidate PR before preparing the next
candidate. Trellis retains changelog fragments during the cycle and consumes
them on stable promotion. Candidate GitHub releases are marked as prereleases.

Automatic pushes to `main` preserve the mode and target of an open release PR.
If no release PR is open and the current version is a candidate, a push prepares
another candidate only when the unreleased fragments have changed since that
candidate's version commit. Automatic pushes do not promote candidates.

Preview candidates locally without changing files:

```sh
just changelog-preview --set gluegun=1.0.0 --pre rc
just changelog-preview --pre rc
just changelog-preview --pre none
```

The last two commands require a candidate version in the local manifest.
The **Auto-tag release** workflow also supports a manual run on `main` to recover
missing tags or GitHub releases. Release preparation requires the
`RELEASE_APP_ID` and `RELEASE_APP_PRIVATE_KEY` Actions secrets; no Hex key is used.

## License

MIT
