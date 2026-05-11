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
just ci            # format-check, check, test, build-strict
just main          # ci plus docs
```

Run a single Startest test or suite after building:

```sh
gleam build
gleam test -- test/client_test.gleam --test-name-filter="collects a single final body"
```

Replace the file path and `--test-name-filter` value with the Startest suite or test name you want to run.

## High-level architecture

`gluegun` is a typed Gleam wrapper around the Erlang Gun HTTP client. The package does not parse URLs: callers open a Gun connection with `connection.open(host, port, options)`, wait for protocol negotiation with `connection.await_up`, then pass request paths to HTTP or WebSocket helpers.

The public API is split by concern:

- `src/gluegun.gleam` is a root facade that re-exports the most common connection, request, response, HTTP helper, and WebSocket functions.
- `gluegun/connection.gleam` owns connection options, transport/protocol/timeout conversion, `open`, `await_up`, `close`, and `shutdown`.
- `gluegun/request.gleam` is the low-level stream API for requests, chunked bodies, cancellation, flow control, and flushing.
- `gluegun/message.gleam` decodes asynchronous Gun stream messages into typed Gleam `Message` and `Frame` values.
- `gluegun/client.gleam` is the high-level HTTP helper layer. It sends one request on an existing connection and collects the full response body, trailers, and informational `1xx` responses in memory.
- `gluegun/websocket.gleam` wraps Gun WebSocket upgrade/send/receive operations.

The Erlang FFI boundary is centralized in `src/gluegun_ffi.erl` and the `@external(erlang, "gluegun_ffi", ...)` declarations in the Gleam modules. Gleam code converts typed options to `dynamic.Dynamic`, Erlang calls Gun and normalizes results, then Gleam decodes maps/tuples back into `Result(_, error.GluegunError)`.

`Connection` and `Stream` are opaque wrappers over raw Erlang dynamic values in `gluegun/internal.gleam`; use the internal constructors/accessors only for FFI plumbing or deterministic tests.

Examples under `examples/` are source-level documentation, not standalone packages and not built by the root `just` tasks.

## Key conventions

- Keep the package Erlang-target-only. Gun is Erlang-only and `gleam.toml` sets `target = "erlang"`.
- Public operations should return `Result(_, error.GluegunError)` and route FFI errors through `error.decode_ffi_error` or `gluegun/internal/ffi_result.gleam`.
- Model option values as opaque Gleam types with builder functions, then convert to Gun-compatible maps at the FFI boundary.
- Normalize HTTP header names before crossing or decoding the Gun boundary; preserve header values.
- Use `client` helpers only for regular HTTP responses collected in memory. Streaming bodies, HTTP/2 push, upgrades, WebSocket messages, cancellation, and flow-control updates belong in `request`/`message`.
- WebSocket support is HTTP/1.1 only. Prefer `websocket.upgrade_with_protocol` after `connection.await_up`; it rejects `Http2` before calling Gun. After a successful HTTP/1.1 upgrade, treat that connection as exclusively WebSocket.
- Erlang FFI helpers should normalize Gun tuples/errors into shapes the Gleam decoders already expect, convert iodata to binaries where needed, and validate WebSocket text frames as UTF-8.
- Tests use Startest with public describe functions ending in `_tests` under `test/`. Raw FFI shape and WebSocket frame tests use Erlang helper modules in `test/*.erl`.
- `@internal` Gleam helpers are intentionally exposed for deterministic unit tests; avoid expanding the public API surface unless the README/docs need to expose the behavior.
