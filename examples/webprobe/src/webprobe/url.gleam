import gleam/int
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam/uri

pub type ParsedUrl {
  ParsedUrl(host: String, port: Int, path: String, tls: Bool)
}

pub fn parse(input: String) -> Result(ParsedUrl, String) {
  use parsed <- result.try(
    uri.parse(input)
    |> result.map_error(fn(_) { "Invalid URL" }),
  )

  let uri.Uri(
    scheme: scheme,
    host: host,
    port: port,
    path: path,
    query: query,
    ..,
  ) = parsed

  case host, scheme {
    Some(host), Some("http") ->
      Ok(ParsedUrl(
        host: host,
        port: option_port(port, 80),
        path: request_path(path, query),
        tls: False,
      ))

    Some(host), Some("https") ->
      Ok(ParsedUrl(
        host: host,
        port: option_port(port, 443),
        path: request_path(path, query),
        tls: True,
      ))

    None, _ -> Error("URL must include a host")
    _, Some(_) -> Error("Only http:// and https:// URLs are supported")
    _, None -> Error("Only http:// and https:// URLs are supported")
  }
}

fn option_port(port: option.Option(Int), default: Int) -> Int {
  case port {
    Some(port) -> port
    None -> default
  }
}

fn request_path(path: String, query: option.Option(String)) -> String {
  let path = case string.is_empty(path) {
    True -> "/"
    False -> path
  }

  case query {
    Some(query) -> path <> "?" <> query
    None -> path
  }
}

pub fn origin(parsed: ParsedUrl) -> String {
  let scheme = case parsed.tls {
    True -> "https://"
    False -> "http://"
  }

  scheme <> parsed.host <> ":" <> int.to_string(parsed.port)
}
