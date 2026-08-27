import gleam/result
import gluegun/client
import gluegun/connection
import gluegun/error
import gluegun/response
import webprobe/cli.{type Config}
import webprobe/report
import webprobe/url.{type ParsedUrl}

pub fn connect_options(
  config: Config,
  parsed_url: ParsedUrl,
) -> connection.ConnectOptions {
  let transport = case parsed_url.tls {
    True -> connection.Tls
    False -> connection.Tcp
  }

  let options =
    connection.options()
    |> connection.with_transport(transport)
    |> connection.with_connect_timeout(config.timeout)
    |> connection.with_retry(config.timeout)

  case config.prefer_http2 && parsed_url.tls {
    True ->
      options |> connection.with_protocols([connection.Http2, connection.Http1])
    False -> options
  }
}

pub fn build_request(config: Config, parsed_url: ParsedUrl) -> client.Request {
  client.new(config.method, parsed_url.path)
  |> client.with_headers(headers: config.headers)
  |> client.with_timeout(timeout: config.timeout)
}

pub fn run(config: Config) -> Result(String, String) {
  use parsed_url <- result.try(url.parse(config.url))

  case
    connect_options(config, parsed_url)
    |> connection.open(host: parsed_url.host, port: parsed_url.port)
  {
    Ok(connection) -> run_on_connection(config, parsed_url, connection)
    Error(error) -> Error("connection failed: " <> error_to_string(error))
  }
}

fn run_on_connection(
  config: Config,
  parsed_url: ParsedUrl,
  connection: connection.Connection,
) -> Result(String, String) {
  case connection.await_up(connection, config.timeout) {
    Ok(protocol) -> {
      case
        build_request(config, parsed_url) |> client.send(connection: connection)
      {
        Ok(response) ->
          close_after_success(connection, protocol, config, response)
        Error(error) ->
          close_after_error(
            connection,
            "request failed: " <> error_to_string(error),
          )
      }
    }

    Error(error) ->
      close_after_error(
        connection,
        "connection failed: " <> error_to_string(error),
      )
  }
}

fn close_after_success(
  connection: connection.Connection,
  protocol: connection.Protocol,
  config: Config,
  response: response.Response,
) -> Result(String, String) {
  case connection.close(connection) {
    Ok(Nil) ->
      Ok(report.format(
        protocol: protocol,
        status: response.status(response),
        headers: response.headers(response),
        body: response.body(response),
        body_preview_bytes: config.body_preview_bytes,
      ))

    Error(error) -> Error("close failed: " <> error_to_string(error))
  }
}

fn close_after_error(
  connection: connection.Connection,
  message: String,
) -> Result(String, String) {
  case connection.close(connection) {
    Ok(Nil) -> Error(message)
    Error(error) ->
      Error(message <> "; close failed: " <> error_to_string(error))
  }
}

pub fn error_to_string(error: error.GluegunError) -> String {
  case error {
    error.Timeout -> "timeout"
    error.ConnectionDown(reason) -> "connection down: " <> reason
    error.ConnectionError(reason) -> "connection error: " <> reason
    error.StreamError(reason) -> "stream error: " <> reason
    error.InvalidOptions(reason) -> "invalid options: " <> reason
    error.InvalidMessage(reason) -> "invalid message: " <> reason
    error.ErlangError(reason) -> "erlang error: " <> reason
    error.DecodeError(reason) -> "decode error: " <> reason
    error.UnsupportedFeature(reason) -> "unsupported feature: " <> reason
  }
}
