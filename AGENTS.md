# Agent instructions for gluegun

## Build, test, and lint commands

This is a Gleam package targeting Erlang only. Tool versions are pinned in `.mise.toml`. The shared CI setup action uses mise to install them, including OTP 27.2.1, rebar3 3.26.0, and Gleam 1.14.0.

```sh
just deps          # gleam deps download
just build         # gleam build
just build-strict  # gleam build --warnings-as-errors
just check         # gleam check
just test          # gleam test
just test-release  # check release preparation without external writes
just examples-test # test standalone examples with test directories
just format        # gleam format src test
just format-check  # gleam format --check src test
just docs          # gleam docs build
just docs-examples # compile complete docs examples and check HTTP cleanup
just site-deps     # install website dependencies
just site-build    # build website
just site-check    # validate website
just site-dev      # start local website dev server
just site-preview  # preview built website
just site-clean    # remove website build artifacts
just ci            # format-check, check, test, test-release, examples-format-check, examples-test, build-strict, trellis-doctor
just main          # ci, examples-build, docs, site-check, site-build
```

Run a test file or a single Unitest test:

```sh
gleam test -- test/client_test.gleam
gleam test -- --test client_test.response_collection_collects_a_single_final_body_test
gleam test -- --seed 123
```

Use `--test module.function` to select a public test function, or append `:LINE` to a file path to select the test at that line. Unitest reports its random seed; pass `--seed` to repeat the order. Tests run sequentially by default. Do not pass `--workers` for normal checks: even `--workers 1` runs tests concurrently within modules, and shared TLS cache checks and tight integration deadlines need sequential execution.

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

Examples under `examples/` are standalone Erlang-target Gleam packages and Trellis workspace members. Their `workspace` release lifecycle excludes them from changelogs, version bumps, tags, and publishing. Each can be built with `gleam build` and run with `gleam run` from its directory. Root `just` recipes use `trellis exec --serial` for package execution, without Trellis task definitions. Trellis 1.5 accepts exact package names, not path selectors, so each command checks its package path before it runs example work. These tasks exclude the root package; `examples-test` runs only packages with test directories, and `examples-build` also packages escripts when a package depends on `gleescript`. `just ci` checks example formatting and runs their tests; `just main` also builds examples.

Keep `examples-deps` and `examples-build` serial: the pinned Gleam compiler can
race when concurrent packages write to its shared Hex cache.

Quick Start and the HTTP/2 guide display complete canonical modules from
`examples/basic_request/src/basic_request/guide.gleam` and
`examples/http2_preferred/src/http2_preferred/guide.gleam` through direct MDX
`?raw` imports and Starlight `Code`. Keep their code in those modules, not in
the pages. The existing example CLI entry points are separate and unchanged.

`just docs-examples` runs Python wiring tests and checks both raw imports and
direct `Code` bindings. It compiles the canonical example packages as path
dependencies, without source changes. It also extracts remaining
import-and-function Gleam blocks from the README and website guides into a
temporary package and checks the landing-page Code component's function body
with its imports. Partial expression snippets are excluded. Only remaining
owned fences get test-only endpoint and cleanup rewrites. The lifecycle harness
uses a loopback peer to check repeated-call cleanup and error precedence.

## Key conventions

- Keep the package Erlang-target-only. Gun is Erlang-only and `gleam.toml` sets `target = "erlang"`.
- Public operations should return `Result(_, error.GluegunError)`; `gluegun_ffi.erl` classifies Gun failures and builds the error variant, so no Gleam code decodes untyped error terms.
- Never use `gleam/dynamic.Dynamic` to describe an FFI value. Model option values as opaque Gleam types with builder functions, convert them to typed encoded-option lists at the FFI boundary, and let Erlang build the Gun-compatible maps.
- Give each foreign Erlang value its own external type (connection process, stream reference, raw Gun message, protocol handler options) so unrelated handles cannot be mixed.
- Normalize HTTP header names before crossing or decoding the Gun boundary; preserve header values.
- Use `client` helpers only for regular HTTP responses collected in memory. Streaming bodies, HTTP/2 push, upgrades, WebSocket messages, cancellation, and flow-control updates belong in `request`/`message`.
- WebSocket support is HTTP/1.1 only. Prefer `websocket.upgrade_with_protocol` after `connection.await_up`; it rejects `Http2` before calling Gun. After a successful HTTP/1.1 upgrade, treat that connection as exclusively WebSocket.
- Erlang FFI helpers should build Gleam values directly (messages, frames, errors), convert iodata to binaries where needed, lowercase header names, and validate WebSocket text frames as UTF-8.
- Tests use Unitest with public zero-argument functions ending in `_test` under `test/`, native Gleam `assert` and `let assert`, and a `unitest.main()` entry point. Each case, including each generated payload combination, has its own test function. Raw FFI shape and WebSocket frame tests use Erlang helper modules in `test/*.erl`, which expose typed constructors (Gun handles, raw Gun messages and frames, typed projections of Gun option maps) rather than untyped terms.
- `@internal` Gleam helpers are intentionally exposed for deterministic unit tests; avoid expanding the public API surface unless the README/docs need to expose the behavior.
