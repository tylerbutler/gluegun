# webprobe

`webprobe` is a small HTTP diagnostics CLI that demonstrates using Gluegun from
a real Gleam command-line application.

It opens a Gun connection with Gluegun, waits for protocol negotiation, sends one
HTTP request, collects the response, and prints the negotiated protocol, status,
headers, and a response body preview.

The command exits with status `0` after a complete HTTP response, including
HTTP 4xx and 5xx responses, or when you use `--help` or `-h`. Invalid arguments,
invalid URLs, connection failures, and request failures return a nonzero exit
status. Help and probe results go to stdout; errors go to stderr.

## Usage

```sh
gleam run -- https://example.com/
gleam run -- --http2 https://nghttp2.org/httpbin/get
gleam run -- --method HEAD https://example.com/
gleam run -- --header "accept: application/json" https://api.github.com/
gleam run -- --timeout 750 --body-bytes 128 https://example.com/
```

URLs must use HTTP or HTTPS and include a non-empty host. `--timeout` accepts
0 through 4294967295 milliseconds, inclusive.

## Tests

Run the Unitest suite from this directory:

```sh
gleam test
gleam test -- --seed 123
gleam test -- test/webprobe_test.gleam
```

Tests use native Gleam assertions and run sequentially. From the repository root,
`just examples-test` runs the example suites, and `just ci` includes them.

## Packaging

Build a single escript file with `gleescript`:

```sh
gleam build
gleam run -m gleescript -- --out=dist
./dist/webprobe --help
python3 -B test/webprobe_process_test.py
```

The Python checks run the packaged executable against local peers. They check
exit status, help output, usage errors, connection and request failures, and
complete HTTP 200, 404, and 500 responses. `just examples-build` also runs them.

The generated escript is a single executable file, but it still requires an
Erlang/OTP runtime on the target machine. Package managers such as Homebrew can
distribute it by installing the escript and declaring an Erlang dependency.

## Notes

- CLI parsing uses `clip` and `argv`.
- Packaging uses `gleescript`.
- HTTP work uses `gluegun/client` on an explicit `gluegun/connection`.
- `--http2` prefers HTTP/2 only for HTTPS URLs and allows HTTP/1.1 fallback.
