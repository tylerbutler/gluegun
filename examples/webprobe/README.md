# webprobe

`webprobe` is a small HTTP diagnostics CLI that demonstrates using Gluegun from
a real Gleam command-line application.

It opens a Gun connection with Gluegun, waits for protocol negotiation, sends one
HTTP request, collects the response, and prints the negotiated protocol, status,
headers, and a response body preview.

## Usage

```sh
gleam run -- https://example.com/
gleam run -- --http2 https://nghttp2.org/httpbin/get
gleam run -- --method HEAD https://example.com/
gleam run -- --header "accept: application/json" https://api.github.com/
gleam run -- --timeout 750 --body-bytes 128 https://example.com/
```

## Packaging

Build a single escript file with `gleescript`:

```sh
gleam build
gleam run -m gleescript -- --out=dist
./dist/webprobe --help
```

The generated escript is a single executable file, but it still requires an
Erlang/OTP runtime on the target machine. Package managers such as Homebrew can
distribute it by installing the escript and declaring an Erlang dependency.

## Notes

- CLI parsing uses `clip` and `argv`.
- Packaging uses `gleescript`.
- HTTP work uses `gluegun/client` on an explicit `gluegun/connection`.
- `--http2` prefers HTTP/2 only for HTTPS URLs and allows HTTP/1.1 fallback.
