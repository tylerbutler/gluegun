import clip
import clip/arg
import clip/flag
import clip/help
import clip/opt
import gleam/list
import gleam/result
import gleam/string
import gluegun/connection
import gluegun/request

pub type Config {
  Config(
    url: String,
    method: request.Method,
    headers: List(request.Header),
    timeout: connection.Timeout,
    prefer_http2: Bool,
    body_preview_bytes: Int,
  )
}

type ParsedFlags {
  ParsedFlags(
    method: request.Method,
    timeout_ms: Int,
    prefer_http2: Bool,
    body_preview_bytes: Int,
    url: String,
  )
}

pub fn parse(args: List(String)) -> Result(Config, String) {
  case args {
    ["--help", ..] | ["-h", ..] -> Error(help_text())
    _ -> parse_config(args)
  }
}

fn parse_config(args: List(String)) -> Result(Config, String) {
  use #(headers, args) <- result.try(extract_headers(args, []))
  use flags <- result.try(command() |> clip.run(args))

  Ok(Config(
    url: flags.url,
    method: flags.method,
    headers: headers,
    timeout: connection.Milliseconds(flags.timeout_ms),
    prefer_http2: flags.prefer_http2,
    body_preview_bytes: flags.body_preview_bytes,
  ))
}

pub fn help_text() -> String {
  "webprobe\n\n"
  <> "  Probe an HTTP endpoint with gluegun and print connection diagnostics.\n\n"
  <> "Usage:\n\n"
  <> "  webprobe [OPTIONS] URL\n\n"
  <> "Arguments:\n\n"
  <> "  URL                       HTTP or HTTPS URL to probe\n\n"
  <> "Options:\n\n"
  <> "  [--method,-X METHOD]      HTTP method to send (default: GET)\n"
  <> "  [--header,-H HEADER]      Request header; repeat for multiple headers\n"
  <> "  [--timeout TIMEOUT]       Connection and request timeout in milliseconds (default: 5000)\n"
  <> "  [--body-bytes BODY-BYTES] Maximum response body bytes to print (default: 512)\n"
  <> "  [--http2]                 Prefer HTTP/2 over TLS, falling back to HTTP/1.1\n"
  <> "  [--help,-h]               Print this help\n"
}

fn command() -> clip.Command(ParsedFlags) {
  clip.command({
    use method <- clip.parameter
    use timeout_ms <- clip.parameter
    use prefer_http2 <- clip.parameter
    use body_preview_bytes <- clip.parameter
    use url <- clip.parameter

    ParsedFlags(method, timeout_ms, prefer_http2, body_preview_bytes, url)
  })
  |> clip.opt(method_opt())
  |> clip.opt(timeout_opt())
  |> clip.flag(http2_flag())
  |> clip.opt(body_bytes_opt())
  |> clip.arg(arg.new("url") |> arg.help("HTTP or HTTPS URL to probe"))
  |> clip.help(help.simple(
    "webprobe",
    "Probe an HTTP endpoint with gluegun and print connection diagnostics.",
  ))
}

fn method_opt() -> opt.Opt(request.Method) {
  opt.new("method")
  |> opt.short("X")
  |> opt.help("HTTP method to send")
  |> opt.try_map(method_from_string)
  |> opt.default(request.Get)
}

fn timeout_opt() -> opt.Opt(Int) {
  opt.new("timeout")
  |> opt.help("Connection and request timeout in milliseconds")
  |> opt.int
  |> opt.default(5000)
}

fn body_bytes_opt() -> opt.Opt(Int) {
  opt.new("body-bytes")
  |> opt.help("Maximum response body bytes to print")
  |> opt.int
  |> opt.try_map(non_negative_body_bytes)
  |> opt.default(512)
}

fn non_negative_body_bytes(bytes: Int) -> Result(Int, String) {
  case bytes < 0 {
    True -> Error("Body preview bytes must be zero or greater")
    False -> Ok(bytes)
  }
}

fn http2_flag() -> flag.Flag {
  flag.new("http2")
  |> flag.help("Prefer HTTP/2 over TLS, falling back to HTTP/1.1")
}

pub fn method_from_string(input: String) -> Result(request.Method, String) {
  case string.uppercase(input) {
    "GET" -> Ok(request.Get)
    "HEAD" -> Ok(request.Head)
    "POST" -> Ok(request.Post)
    "PUT" -> Ok(request.Put)
    "PATCH" -> Ok(request.Patch)
    "DELETE" -> Ok(request.Delete)
    "OPTIONS" -> Ok(request.Options)
    "TRACE" -> Ok(request.Trace)
    other -> Error("Unsupported method: " <> other)
  }
}

fn extract_headers(
  args: List(String),
  headers: List(request.Header),
) -> Result(#(List(request.Header), List(String)), String) {
  case args {
    [] -> Ok(#(list.reverse(headers), []))

    ["--header", value, ..rest] | ["-H", value, ..rest] -> {
      use header <- result.try(parse_header(value))
      extract_headers(rest, [header, ..headers])
    }

    ["--header"] | ["-H"] -> Error("Header must use name:value format")

    [arg, ..rest] -> {
      use #(headers, rest) <- result.try(extract_headers(rest, headers))
      Ok(#(headers, [arg, ..rest]))
    }
  }
}

fn parse_header(value: String) -> Result(request.Header, String) {
  case string.split_once(value, on: ":") {
    Ok(#(name, value)) -> {
      let name = name |> string.trim |> string.lowercase
      let value = string.trim(value)

      case string.is_empty(name) {
        True -> Error("Header must use name:value format")
        False -> Ok(#(name, value))
      }
    }

    Error(_) -> Error("Header must use name:value format")
  }
}
