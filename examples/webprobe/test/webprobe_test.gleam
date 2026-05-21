import gleam/option.{Some}
import gleam/string
import gluegun/client
import gluegun/connection
import gluegun/request
import startest.{describe, it}
import startest/expect
import webprobe/cli
import webprobe/report
import webprobe/runner
import webprobe/url

pub fn main() -> Nil {
  startest.run(startest.default_config())
}

pub fn webprobe_tests() {
  describe("webprobe", [
    describe("URL parsing", [
      it("parses an HTTP URL with the default port and root path", fn() {
        url.parse("http://example.com")
        |> expect.to_equal(
          Ok(url.ParsedUrl(host: "example.com", port: 80, path: "/", tls: False)),
        )
      }),
      it("parses an HTTPS URL with path and query", fn() {
        url.parse("https://example.com/search?q=gleam")
        |> expect.to_equal(
          Ok(url.ParsedUrl(
            host: "example.com",
            port: 443,
            path: "/search?q=gleam",
            tls: True,
          )),
        )
      }),
      it("parses explicit ports", fn() {
        url.parse("https://localhost:8443/health")
        |> expect.to_equal(
          Ok(url.ParsedUrl(
            host: "localhost",
            port: 8443,
            path: "/health",
            tls: True,
          )),
        )
      }),
      it("rejects unsupported schemes", fn() {
        url.parse("ftp://example.com")
        |> expect.to_equal(Error("Only http:// and https:// URLs are supported"))
      }),
    ]),
    describe("CLI parsing", [
      it("parses a default GET probe", fn() {
        cli.parse(["https://example.com"])
        |> expect.to_equal(
          Ok(cli.Config(
            url: "https://example.com",
            method: request.Get,
            headers: [],
            timeout: connection.Milliseconds(5000),
            prefer_http2: False,
            body_preview_bytes: 512,
          )),
        )
      }),
      it(
        "parses method, headers, timeout, HTTP/2 preference, and body size",
        fn() {
          cli.parse([
            "--method",
            "HEAD",
            "--header",
            "accept: application/json",
            "--header",
            "x-trace:abc",
            "--timeout",
            "750",
            "--http2",
            "--body-bytes",
            "64",
            "https://example.com/api",
          ])
          |> expect.to_equal(
            Ok(cli.Config(
              url: "https://example.com/api",
              method: request.Head,
              headers: [
                #("accept", "application/json"),
                #("x-trace", "abc"),
              ],
              timeout: connection.Milliseconds(750),
              prefer_http2: True,
              body_preview_bytes: 64,
            )),
          )
        },
      ),
      it("rejects malformed headers", fn() {
        cli.parse(["--header", "missing-colon", "https://example.com"])
        |> expect.to_equal(Error("Header must use name:value format"))
      }),
      it("rejects negative body preview sizes", fn() {
        cli.parse(["--body-bytes", "-1", "https://example.com"])
        |> expect.to_equal(Error("Body preview bytes must be zero or greater"))
      }),
      it("documents the header option in help text", fn() {
        cli.help_text()
        |> string.contains("--header,-H HEADER")
        |> expect.to_equal(True)
      }),
    ]),
    describe("report formatting", [
      it("renders protocol, status, headers, and body preview", fn() {
        report.format(
          protocol: connection.Http2,
          status: 200,
          headers: [#("content-type", "text/plain")],
          body: <<"hello webprobe":utf8>>,
          body_preview_bytes: 5,
        )
        |> expect.to_equal(
          "protocol: HTTP/2\n"
          <> "status: 200\n"
          <> "headers:\n"
          <> "  content-type: text/plain\n"
          <> "body-preview: hello\n",
        )
      }),
      it("renders invalid UTF-8 bodies as byte arrays", fn() {
        report.format(
          protocol: connection.Http1,
          status: 200,
          headers: [],
          body: <<255>>,
          body_preview_bytes: 16,
        )
        |> expect.to_equal(
          "protocol: HTTP/1.1\n"
          <> "status: 200\n"
          <> "headers: none\n"
          <> "body-preview: <<255>>\n",
        )
      }),
    ]),
    describe("runner request construction", [
      it("prefers HTTP/2 only for TLS URLs when requested", fn() {
        let config =
          cli.Config(
            url: "https://example.com",
            method: request.Get,
            headers: [],
            timeout: connection.Milliseconds(5000),
            prefer_http2: True,
            body_preview_bytes: 512,
          )

        let assert Ok(parsed) = url.parse(config.url)

        runner.connect_options(config, parsed)
        |> connection.protocols
        |> expect.to_equal(Some([connection.Http2, connection.Http1]))
      }),
      it("builds the gluegun request from parsed config and URL", fn() {
        let config =
          cli.Config(
            url: "https://example.com/search?q=gleam",
            method: request.Head,
            headers: [#("accept", "application/json")],
            timeout: connection.Milliseconds(750),
            prefer_http2: False,
            body_preview_bytes: 512,
          )

        let assert Ok(parsed) = url.parse(config.url)

        runner.build_request(config, parsed)
        |> client.inspect_request
        |> expect.to_equal(client.RequestFields(
          method: request.Head,
          path: "/search?q=gleam",
          headers: [#("accept", "application/json")],
          body: <<>>,
          options: request.options(),
          timeout: connection.Milliseconds(750),
        ))
      }),
    ]),
  ])
}
