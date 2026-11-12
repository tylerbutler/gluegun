# Gluegun

[![Docs](https://img.shields.io/badge/docs-gluegun.tylerbutler.com-ffaff3)](https://gluegun.tylerbutler.com/)
[![CI](https://github.com/tylerbutler/gluegun/actions/workflows/ci.yml/badge.svg)](https://github.com/tylerbutler/gluegun/actions/workflows/ci.yml)

A Gleam wrapper for the Erlang [Gun](https://ninenines.eu/docs/en/gun/) HTTP client.

Gun is an asynchronous HTTP client supporting HTTP/1.1, HTTP/2, and WebSocket over HTTP/1.1. Gluegun gives Gleam callers typed connection, request, response, message, and WebSocket helpers while preserving access to Gun's stream-oriented model. Because Gun is Erlang-only, Gluegun targets the Erlang runtime.

## Installation

For the 1.0 Hex release, install Gluegun with:

```sh
gleam add gluegun
gleam add gleam_http
```

Add `gleam_http` when you import standard HTTP modules, as the examples do.
Maintainers have configured Hex publication but have not yet published 1.0.
Until that release is available, or to use an unreleased revision, add a Git
dependency to `gleam.toml`:

```toml
[dependencies]
gleam_http = ">= 4.0.0 and < 5.0.0"
gluegun = { git = "https://github.com/tylerbutler/gluegun.git", ref = "main" }
```

For reproducible builds, replace `main` with a release tag or commit SHA.

## Compatibility

- Erlang target only; Gluegun wraps the Erlang Gun client and does not support the JavaScript target.
- Supports Gleam `>= 1.11.0` and Gun `>= 2.1.0 and < 3.0.0`.

Request methods use `gleam/http.Method`, including `Other` for extension
methods. Gluegun keeps its own path-only request builder and response so callers
can access trailers and informational responses without URL parsing.

Connection options default to **zero retries**. Opt in with `with_retry` when
you need HTTP reconnection. After an `await_up` error, call
`connection.terminate` to release any process that remains alive, including
when you selected retries or setup has not finished.

Numeric options reject invalid input with `InvalidOptions`; they do not clamp.
Finite timeouts accept 0 through 4_294_967_295 milliseconds, inclusive, as
supported by OTP 27. Use `connection.infinity()` for no limit. Retry counts
must be non-negative, flow credit must be positive, TLS depth accepts 0 through
255, and ports accept 0 through 65535. Timeout construction returns `Result`
for literals and configuration values alike.

## Security

Gluegun is **secure by default** for TLS. Whenever a connection uses TLS
(`connection.Tls`, or `connection.Auto` resolving to TLS), Gluegun applies a
secure baseline at connection time: peer and hostname verification, system CA
certificates, TLS 1.2/1.3, SNI for DNS hosts, and HTTPS hostname matching.

With `connection.Auto`, connections without TLS options use TLS on port 443
and plain TCP on all other ports. Plain TCP does not load TLS trust roots.
If you configure TLS options under Auto, the connection uses TLS on each
port. TLS setup failures return errors without a fallback to plaintext.

The minimal HTTPS setup is just `connection.options() |> connection.with_transport(transport: connection.Tls)`. Override individual fields with the `tls.with_*` builders; user-supplied values always win.

For development against self-signed endpoints, use `tls.insecure()`, which disables verification and SNI. Do not ship it.

See the [TLS guide](https://gluegun.tylerbutler.com/guides/tls/) for the canonical default list, full details, and overrides.

## Basic GET

Open a Gun connection, wait for it to be ready, send a GET, and collect the full response in memory.

```gleam
import gleam/http
import gleam/int
import gleam/io
import gleam/result
import gluegun/client
import gluegun/connection
import gluegun/response

pub fn main() {
  use timeout <- result.try(connection.milliseconds(5000))

  use conn <- result.try(
    connection.options()
    |> connection.open(host: "example.com", port: 80),
  )
  use _protocol <- result.try(connection.await_up(conn, timeout))

  use res <- result.try(
    client.new(http.Get, "/")
    |> client.with_timeout(timeout: timeout)
    |> client.send(connection: conn),
  )

  io.println("status: " <> int.to_string(res.response.status))

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
import gleam/http
import gluegun/client

fn fetch_json(conn, path, timeout) {
  client.new(http.Get, path)
  |> client.with_header(name: "accept", value: "application/json")
  |> client.with_timeout(timeout: timeout)
  |> client.send(connection: conn)
}
```

`client.with_timeout` sets one total budget for dispatch and response
collection. Informational messages and body chunks do not restart it.
`Infinity` remains unlimited; a zero budget returns `Timeout`.

When collection fails, `client` helpers attempt to cancel that stream and drain its queued messages. They also cancel and drain each promised stream found in a rejected or queued push. They return the original error and keep other streams and the shared connection open. Cleanup failures produce a warning. Cancellation is asynchronous, so messages in transit can arrive after the drain. The high-level helpers do not return the failed stream handle; use the low-level API in a separate receiving process if you need strict mailbox isolation.

## Standard HTTP types

HTTP APIs use `gleam/http.Method`. Requests remain connection-bound: the
connection determines the scheme, host, and port. Pass an encoded request target
such as `/items?tag=a%2Fb&tag=c`; Gluegun does not encode paths or queries.
Request bodies are byte-aligned `BitArray` values and need not be UTF-8.
`client.with_timeout` sets one total budget for dispatch and response collection.

`client.send` returns `gluegun/response.Response(BitArray)`. Its `response` field
is a standard `gleam/http/response.Response(BitArray)`. Trailers and ordered
informational responses remain in separate fields:

```gleam
import gleam/bit_array
import gleam/http/response as http_response
import gleam/result
import gluegun/response

fn decode_body(collected: response.Response(BitArray)) {
  use decoded <- result.try(
    http_response.try_map(collected.response, bit_array.to_string),
  )
  Ok(response.Response(..collected, response: decoded))
}
```

Use standard header and body helpers on `collected.response`. Keep the outer
value when you need trailers or informational responses; selecting only the
standard response excludes that metadata.

### Migration

Replace `request.Get`, `request.Post`, and other method constructors with
`http.Get`, `http.Post`, and the corresponding `gleam/http` constructors.
Replace `request.Custom` with `http.Other` and `request.Method` with
`http.Method`.

Add a body parameter to collected-response type annotations:
`response.Response` becomes `response.Response(BitArray)`. Existing Gluegun
status, header, body, and text accessors still work. Informational responses
now use standard `gleam/http/response.Response(Nil)` values instead of
`response.Informational` constructors.

Standard request converters remain deferred. Gun-specific handles, stream
events, validated options, and lifecycle APIs retain their custom types.

## Small HTTP facade

The root `gluegun` module provides options, timeout construction, open/await,
request/send, body text, and close/shutdown/terminate. Use `client` for header
and body customization, or the named streaming and WebSocket modules.

```gleam
import gleam/http
import gleam/result
import gluegun

pub fn fetch() {
  use timeout <- result.try(gluegun.milliseconds(5000))
  use conn <- result.try(
    gluegun.open(gluegun.connection_options(), host: "localhost", port: 8080),
  )
  let exchange = {
    use _ <- result.try(gluegun.await_up(conn, timeout))
    use res <- result.try(
      gluegun.new_request(http.Get, "/") |> gluegun.send(connection: conn),
    )
    gluegun.body_text(res)
  }
  let cleanup = gluegun.terminate(conn)
  use text <- result.try(exchange)
  use _ <- result.try(cleanup)
  Ok(text)
}
```

## Streaming a request body

Use `gluegun/request` when the request body is produced in chunks. Start with `request.start_stream`, send zero or more chunks with `fin.NoFin`, and complete the body with `fin.Fin`. Response headers and body are separate asynchronous Gun stream messages; use `gluegun/message` helpers or your own receive loop for advanced flows.

Do not set `Content-Length` on a streamed upload. Gluegun rejects it before
sending headers because supported Gun versions can crash on fixed-length
chunk sequences. Use chunked uploads or send the complete body in one request.

```gleam
import gleam/http
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
      http.Post,
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
`with_tls_handshake_timeout` to bound separate setup stages. These settings preserve the TLS verification defaults.
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

Gun supports WebSocket over HTTP/1.1 only. `websocket.connect` forces HTTP/1.1
and zero retries after applying your connection options, including TLS
settings. A dropped connection returns `ConnectionDown`; automatic HTTP
reconnection cannot restore a WebSocket upgrade.

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

`Socket` is reusable and you control its lifecycle. `with_socket` uses the
same teardown and gives callback errors precedence over cleanup errors.
To upgrade an existing connection, use `websocket.upgrade` with its negotiated
protocol and upgrade options, then `await_upgrade` and `from_upgrade`. Use
the same Socket frame and close operations after adoption.

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
- WebSocket over HTTP/2 is unsupported by Gun. Gluegun rejects it in `websocket.upgrade`.
- TLS option surface is intentionally small at first. Advanced TLS options may require future typed additions.
- Gun can leave HTTP/1.1 reads paused after cancellation with exhausted finite
  flow credit. Terminate and replace that connection, discarding its other
  requests. This accepted upstream limitation does not block 1.0; see
  [#78](https://github.com/tylerbutler/gluegun/issues/78) and related
  [ninenines/gun#56](https://github.com/ninenines/gun/issues/56).
- Response header strings must be UTF-8. Invalid wire values return
  `DecodeError` rather than invalid Gleam strings or silently changed bytes.

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

Install the build tools pinned in `.mise.toml` with `mise install` and activate
mise in your shell. CI installs the same tools with `jdx/mise-action`. For website
tasks, run `corepack enable` to use the pnpm version in `website/package.json`.

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
an exact `v{version}` tag and a GitHub release. Tag pushes run CI and package
export without publishing. Trellis uses the `hex` lifecycle; maintainers
must authorize a manual **Hex release** run to publish a 1.0-or-later version,
including release candidates. The workflow excludes 0.x versions from publication.

### Hex release setup

The repository configures Hex publication; an actual release still requires
maintainer authorization. Track publication verification in
[#55](https://github.com/tylerbutler/gluegun/issues/55). Configuration and dry-run
checks do not establish that Hex accepted a package or that HexDocs serves it.

Before the first Hex release:

1. Select the intended 1.0 candidate or stable version through the existing
   release process. Do not overwrite or duplicate `release/pending`.
2. Merge the reviewed release PR and confirm the immutable `v{version}` tag
   points to that commit on `main`. The **Hex release** workflow checks the
   tag against `gleam.toml` and ancestry on `main`, and exports the package. It requires
   CI, compatibility, examples, documentation, and reference freshness checks.
   A push runs these checks only; it does not publish.
3. Build and inspect with `gleam export hex-tarball`. Check `metadata.config`
   and its nested `contents.tar.gz`: include the licence, Gleam modules, and
   `src/gluegun_ffi.erl`; exclude test/compatibility helpers, build output,
   credentials, and development artifacts. Review production dependencies.
   `trellis publish --dry-run --tag v1.0.0` checks tag selection and dependency
   rewrites from the corresponding checkout; it does not replace the test suite.
4. Confirm the repository's `HEXPM_API_KEY` Actions secret contains a scoped
   Hex key with package and documentation publishing access. Read secret names
   with `gh secret list --repo tylerbutler/gluegun`; do not print secret values.
   The required secret names were present during setup, but this check cannot
   establish key validity, scope, or package ownership. Existing
   `RELEASE_APP_ID` and `RELEASE_APP_PRIVATE_KEY` support GitHub release
   operations, not Hex publication. Report missing credentials or access to
   maintainers; configuration work does not authorize secret/settings changes.
5. Only after explicit publication authorization, dispatch **Hex release**
   on the approved tag, for example:

   ```sh
   gh workflow run publish.yml --repo tylerbutler/gluegun --ref v1.0.0
   ```

   Do not run it on a branch. The workflow checks the tagged source again,
   runs `trellis publish --tag "$RELEASE_TAG"` with `HEXPM_API_KEY`, then
   runs `gleam docs publish` for that same version. Trellis calls
   `gleam publish --yes`, which uploads the package and API documentation.
   The explicit docs step also completes documentation after a partial upload
   where Trellis skips an existing Hex version.
6. Confirm the version on [Hex](https://hex.pm/packages/gluegun) and its API
   reference at `https://hexdocs.pm/gluegun/<version>/`. Remove the pending
   publication notice from installation instructions after this verification.

If publication fails, retain the approved tag and inspect whether Hex
accepted the version before retrying. Do not retag or overwrite a published
version. After confirming the accepted package matches the approved tag,
maintainers can authorize another manual run on the same tag. Trellis skips
existing Hex versions; the docs step uploads documentation for that version.
Do not use `--replace` as a recovery shortcut.

### Website reference builds

Commit the generated API pages under `website/src/content/docs/reference/`
and `website/reference-state.json` with changes to source files, `gleam.toml`,
`manifest.toml`, the reference generator, or `.mise.toml`.

Install the tools listed in `.mise.toml` and enable Corepack for the pnpm
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
The fingerprint supports `.mise.toml` and `.tool-versions` and detects adding,
removing, or migrating these files. It hashes the full files, so any tool
configuration change requires regeneration. Keep at least one supported pin
file; missing tool configuration or required source inputs stop the build.

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
`RELEASE_APP_ID` and `RELEASE_APP_PRIVATE_KEY` Actions secrets. Those workflows
do not use the Hex key; the separate manual **Hex release** publish job uses
`HEXPM_API_KEY`.

## License

MIT
