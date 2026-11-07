import gleam/option.{Some}
import gleam/string
import gluegun/client
import gluegun/connection
import gluegun/request
import unitest
import webprobe/cli
import webprobe/report
import webprobe/runner
import webprobe/url

pub fn main() -> Nil {
  unitest.main()
}

pub fn url_parsing_parses_an_http_url_with_the_default_port_and_root_path_test() -> Nil {
  let actual_1 = url.parse("http://example.com")
  let expected_1 =
    Ok(url.ParsedUrl(host: "example.com", port: 80, path: "/", tls: False))
  let assert #(True, _, _) = #(actual_1 == expected_1, actual_1, expected_1)
  Nil
}

pub fn url_parsing_parses_an_https_url_with_path_and_query_test() -> Nil {
  let actual_2 = url.parse("https://example.com/search?q=gleam")
  let expected_2 =
    Ok(url.ParsedUrl(
      host: "example.com",
      port: 443,
      path: "/search?q=gleam",
      tls: True,
    ))
  let assert #(True, _, _) = #(actual_2 == expected_2, actual_2, expected_2)
  Nil
}

pub fn url_parsing_parses_explicit_ports_test() -> Nil {
  let actual_3 = url.parse("https://localhost:8443/health")
  let expected_3 =
    Ok(url.ParsedUrl(host: "localhost", port: 8443, path: "/health", tls: True))
  let assert #(True, _, _) = #(actual_3 == expected_3, actual_3, expected_3)
  Nil
}

pub fn url_parsing_rejects_unsupported_schemes_test() -> Nil {
  let actual_4 = url.parse("ftp://example.com")
  let expected_4 = Error("Only http:// and https:// URLs are supported")
  let assert #(True, _, _) = #(actual_4 == expected_4, actual_4, expected_4)
  Nil
}

pub fn cli_parsing_parses_a_default_get_probe_test() -> Nil {
  let actual_5 = cli.parse(["https://example.com"])
  let expected_5 =
    Ok(cli.Config(
      url: "https://example.com",
      method: request.Get,
      headers: [],
      timeout: timeout(5000),
      prefer_http2: False,
      body_preview_bytes: 512,
    ))
  let assert #(True, _, _) = #(actual_5 == expected_5, actual_5, expected_5)
  Nil
}

pub fn cli_parsing_parses_method_headers_timeout_http_2_preference_and_body_size_test() -> Nil {
  let actual_6 =
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
  let expected_6 =
    Ok(cli.Config(
      url: "https://example.com/api",
      method: request.Head,
      headers: [
        #("accept", "application/json"),
        #("x-trace", "abc"),
      ],
      timeout: timeout(750),
      prefer_http2: True,
      body_preview_bytes: 64,
    ))
  let assert #(True, _, _) = #(actual_6 == expected_6, actual_6, expected_6)
  Nil
}

pub fn cli_parsing_rejects_malformed_headers_test() -> Nil {
  let actual_7 = cli.parse(["--header", "missing-colon", "https://example.com"])
  let expected_7 = Error("Header must use name:value format")
  let assert #(True, _, _) = #(actual_7 == expected_7, actual_7, expected_7)
  Nil
}

pub fn cli_parsing_rejects_negative_body_preview_sizes_test() -> Nil {
  let actual_8 = cli.parse(["--body-bytes", "-1", "https://example.com"])
  let expected_8 = Error("Body preview bytes must be zero or greater")
  let assert #(True, _, _) = #(actual_8 == expected_8, actual_8, expected_8)
  Nil
}

pub fn cli_parsing_rejects_negative_timeouts_test() -> Nil {
  let actual_9 = cli.parse(["--timeout", "-1", "https://example.com"])
  let expected_9 = Error("Timeout must be zero or greater")
  let assert #(True, _, _) = #(actual_9 == expected_9, actual_9, expected_9)
  Nil
}

pub fn cli_parsing_documents_the_header_option_in_help_text_test() -> Nil {
  let actual_10 = {
    cli.help_text()
    |> string.contains("--header,-H HEADER")
  }
  let expected_10 = True
  let assert #(True, _, _) = #(actual_10 == expected_10, actual_10, expected_10)
  Nil
}

pub fn report_formatting_renders_protocol_status_headers_and_body_preview_test() -> Nil {
  let actual_11 =
    report.format(
      protocol: connection.Http2,
      status: 200,
      headers: [#("content-type", "text/plain")],
      body: <<"hello webprobe":utf8>>,
      body_preview_bytes: 5,
    )
  let expected_11 =
    "protocol: HTTP/2\n"
    <> "status: 200\n"
    <> "headers:\n"
    <> "  content-type: text/plain\n"
    <> "body-preview: hello\n"
  let assert #(True, _, _) = #(actual_11 == expected_11, actual_11, expected_11)
  Nil
}

pub fn report_formatting_renders_invalid_utf_8_bodies_as_byte_arrays_test() -> Nil {
  let actual_12 =
    report.format(
      protocol: connection.Http1,
      status: 200,
      headers: [],
      body: <<255>>,
      body_preview_bytes: 16,
    )
  let expected_12 =
    "protocol: HTTP/1.1\n"
    <> "status: 200\n"
    <> "headers: none\n"
    <> "body-preview: <<255>>\n"
  let assert #(True, _, _) = #(actual_12 == expected_12, actual_12, expected_12)
  Nil
}

pub fn runner_request_construction_prefers_http_2_only_for_tls_urls_when_requested_test() -> Nil {
  let config =
    cli.Config(
      url: "https://example.com",
      method: request.Get,
      headers: [],
      timeout: timeout(5000),
      prefer_http2: True,
      body_preview_bytes: 512,
    )

  let assert Ok(parsed) = url.parse(config.url)

  let actual_13 = {
    runner.connect_options(config, parsed)
    |> connection.protocols
  }
  let expected_13 = Some([connection.Http2, connection.Http1])
  let assert #(True, _, _) = #(actual_13 == expected_13, actual_13, expected_13)
  Nil
}

pub fn runner_request_construction_builds_the_gluegun_request_from_parsed_config_and_url_test() -> Nil {
  let config =
    cli.Config(
      url: "https://example.com/search?q=gleam",
      method: request.Head,
      headers: [#("accept", "application/json")],
      timeout: timeout(750),
      prefer_http2: False,
      body_preview_bytes: 512,
    )

  let assert Ok(parsed) = url.parse(config.url)

  let actual_14 = {
    runner.build_request(config, parsed)
    |> client.inspect_request
  }
  let expected_14 =
    client.RequestFields(
      method: request.Head,
      path: "/search?q=gleam",
      headers: [#("accept", "application/json")],
      body: <<>>,
      options: request.options(),
      timeout: timeout(750),
    )
  let assert #(True, _, _) = #(actual_14 == expected_14, actual_14, expected_14)
  Nil
}

fn timeout(milliseconds: Int) -> connection.Timeout {
  let assert Ok(timeout) = connection.milliseconds(milliseconds)
  timeout
}
