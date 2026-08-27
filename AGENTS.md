# Agent instructions for gluegun

## Build, test, and lint commands

This is a Gleam package targeting Erlang only. Tool versions are pinned in `.tool-versions` and CI uses OTP 27.2.1, rebar3 3.26.0, and Gleam 1.14.0.

```sh
just deps          # gleam deps download
just build         # gleam build
just build-strict  # gleam build --warnings-as-errors
just check         # gleam check
just test          # gleam test
just format        # gleam format src test
just format-check  # gleam format --check src test
just docs          # gleam docs build
just site-deps     # install website dependencies
just site-build    # build website
just site-check    # validate website
just site-dev      # start local website dev server
just site-preview  # preview built website
just site-clean    # remove website build artifacts
just ci            # format-check, check, test, build-strict
just main          # ci, examples-format-check, examples-build, docs, site-check, site-build
```

Run a single Startest test or suite after building:

```sh
gleam build
gleam test -- test/client_test.gleam --test-name-filter="collects a single final body"
```

Replace the file path and `--test-name-filter` value with the Startest suite or test name you want to run.

## High-level architecture

Gluegun is a typed Gleam wrapper around the Erlang Gun HTTP client. The package does not parse URLs: callers open a Gun connection with `connection.options() |> connection.open(host: "example.com", port: 443)`, wait for protocol negotiation with `connection.await_up`, then pass request paths to HTTP or WebSocket helpers.

The public API is split by concern:

- `src/gluegun.gleam` is a root facade that re-exports the most common connection, request, response, HTTP helper, and WebSocket functions.
- `gluegun/connection.gleam` owns connection options, transport/protocol/timeout conversion, `open`, `await_up`, `close`, and `shutdown`.
- `gluegun/request.gleam` is the low-level stream API for requests, chunked bodies, cancellation, flow control, and flushing.
- `gluegun/message.gleam` decodes asynchronous Gun stream messages into typed Gleam `Message` and `Frame` values.
- `gluegun/client.gleam` is the high-level HTTP helper layer. It sends one request on an existing connection and collects the full response body, trailers, and informational `1xx` responses in memory.
- `gluegun/websocket.gleam` wraps Gun WebSocket upgrade/send/receive operations.

The Erlang FFI boundary is centralized in `src/gluegun_ffi.erl` and the `@external(erlang, "gluegun_ffi", ...)` declarations in the Gleam modules. Nothing crosses that boundary untyped: Gleam encodes options as typed values (`connection.ConnectOption`, `tls.TlsSetting`, `websocket.UpgradeOption`, `connection.Timeout`, `fin.Fin`, `message.Frame`), `gluegun_ffi.erl` converts them to Gun terms, and every FFI function returns `Result(value, error.GluegunError)` with the Gleam error variant built in Erlang.

`Connection` and `Stream` are external foreign types declared in `gluegun/internal.gleam`: they name a Gun connection process identifier and a Gun stream reference, have no Gleam constructors, and can only come from Gun (or, in tests, from typed constructors in `test/gluegun_ffi_test.erl`).

Examples under `examples/` are standalone Erlang-target Gleam packages; each can be built with `gleam build` and run with `gleam run` from its directory. Root `just` recipes `examples-deps`, `examples-format-check`, and `examples-build` operate on examples; `just main` includes example validation.

## Key conventions

- Keep the package Erlang-target-only. Gun is Erlang-only and `gleam.toml` sets `target = "erlang"`.
- Public operations should return `Result(_, error.GluegunError)`; `gluegun_ffi.erl` classifies Gun failures and builds the error variant, so no Gleam code decodes untyped error terms.
- Never use `gleam/dynamic.Dynamic` to describe an FFI value. Model option values as opaque Gleam types with builder functions, convert them to typed encoded-option lists at the FFI boundary, and let Erlang build the Gun-compatible maps.
- Give each foreign Erlang value its own external type (connection process, stream reference, raw Gun message, protocol handler options) so unrelated handles cannot be mixed.
- Normalize HTTP header names before crossing or decoding the Gun boundary; preserve header values.
- Use `client` helpers only for regular HTTP responses collected in memory. Streaming bodies, HTTP/2 push, upgrades, WebSocket messages, cancellation, and flow-control updates belong in `request`/`message`.
- WebSocket support is HTTP/1.1 only. Prefer `websocket.upgrade_with_protocol` after `connection.await_up`; it rejects `Http2` before calling Gun. After a successful HTTP/1.1 upgrade, treat that connection as exclusively WebSocket.
- Erlang FFI helpers should build Gleam values directly (messages, frames, errors), convert iodata to binaries where needed, lowercase header names, and validate WebSocket text frames as UTF-8.
- Tests use Startest with public describe functions ending in `_tests` under `test/`. Raw FFI shape and WebSocket frame tests use Erlang helper modules in `test/*.erl`, which expose typed constructors (Gun handles, raw Gun messages and frames, typed projections of Gun option maps) rather than untyped terms.
- `@internal` Gleam helpers are intentionally exposed for deterministic unit tests; avoid expanding the public API surface unless the README/docs need to expose the behavior.
