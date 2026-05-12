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
    Ok(conn) -> run_on_connection(config, parsed_url, conn)
    Error(err) -> Error("connection failed: " <> error_to_string(err))
  }
}

fn run_on_connection(config: Config, parsed_url: ParsedUrl, conn) {
  case connection.await_up(conn, config.timeout) {
    Ok(protocol) -> {
      case build_request(config, parsed_url) |> client.send(connection: conn) {
        Ok(res) -> close_after_success(conn, protocol, config, res)
        Error(err) ->
          close_after_error(conn, "request failed: " <> error_to_string(err))
      }
    }

    Error(err) ->
      close_after_error(conn, "connection failed: " <> error_to_string(err))
  }
}

fn close_after_success(
  conn,
  protocol: connection.Protocol,
  config: Config,
  res: response.Response,
) {
  case connection.close(conn) {
    Ok(Nil) ->
      Ok(report.format(
        protocol: protocol,
        status: response.status(res),
        headers: response.headers(res),
        body: response.body(res),
        body_preview_bytes: config.body_preview_bytes,
      ))

    Error(err) -> Error("close failed: " <> error_to_string(err))
  }
}

fn close_after_error(conn, message: String) -> Result(String, String) {
  case connection.close(conn) {
    Ok(Nil) -> Error(message)
    Error(err) -> Error(message <> "; close failed: " <> error_to_string(err))
  }
}

pub fn error_to_string(err: error.GluegunError) -> String {
  case err {
    error.Timeout -> "timeout"
    error.ConnectionDown(reason) -> "connection down: " <> reason
    error.ConnectionError(reason) -> "connection error: " <> reason
    error.StreamError(reason) -> "stream error: " <> reason
    error.InvalidOptions(reason) -> "invalid options: " <> reason
    error.InvalidMessage(reason) -> "invalid message: " <> reason
    error.ErlangError(reason) -> "erlang error: " <> reason
    error.DecodeError(reason) -> "decode error: " <> reason
  }
}
