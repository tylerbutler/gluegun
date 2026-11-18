import gleam/bit_array
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gluegun/connection
import webprobe/cli
import webprobe/runner
import webprobe/url

// Scoped SSL listener, not interchangeable with a Gun connection.
type HelloListener

@external(erlang, "webprobe_protocol_test_ffi", "with_listener")
fn with_listener(
  callback: fn(HelloListener, Int) -> Result(a, String),
) -> Result(a, String)

// Takes ownership of the connection returned by open, including on failure.
@external(erlang, "webprobe_protocol_test_ffi", "capture_client_hello")
fn capture_client_hello(
  listener: HelloListener,
  open: fn() -> Result(connection.Connection, String),
) -> Result(BitArray, String)

pub fn default_https_client_hello_offers_only_http_1_test() -> Nil {
  let actual = offered_protocols([])
  let expected = Ok(["http/1.1"])
  let assert #(True, _, _) = #(actual == expected, actual, expected)
  Nil
}

pub fn http2_https_client_hello_offers_exactly_both_protocols_test() -> Nil {
  let actual = offered_protocols(["--http2"])
  // Compare sorted lists, not sets: duplicates and extra offers must fail,
  // but wire ordering is deliberately outside this regression's contract.
  let expected = Ok(["h2", "http/1.1"])
  let assert #(True, _, _) = #(actual == expected, actual, expected)
  Nil
}

fn offered_protocols(flags: List(String)) -> Result(List(String), String) {
  let captured =
    with_listener(fn(listener, port) {
      capture_client_hello(listener, fn() {
        let endpoint = "https://127.0.0.1:" <> int.to_string(port) <> "/"
        use command <- result.try(cli.parse(list.append(flags, [endpoint])))
        let assert cli.Probe(config) = command
        use parsed <- result.try(url.parse(config.url))
        runner.connect_options(config, parsed)
        |> connection.open(host: parsed.host, port: parsed.port)
        |> result.map_error(runner.error_to_string)
      })
    })

  // All resources have been released before decoding or asserting.
  use encoded <- result.try(captured)
  use protocols <- result.try(decode_protocols(encoded))
  Ok(list.sort(protocols, string.compare))
}

// OTP exposes ALPN as the RFC 7301 length-prefixed protocol names, without
// the outer extension/list lengths. Validate UTF-8 before producing Strings.
fn decode_protocols(encoded: BitArray) -> Result(List(String), String) {
  case encoded {
    <<>> -> Ok([])
    <<length:8, name:size(length)-bytes, rest:bits>> if length > 0 -> {
      use name <- result.try(
        bit_array.to_string(name)
        |> result.map_error(fn(_) { "ALPN protocol is not UTF-8" }),
      )
      use rest <- result.try(decode_protocols(rest))
      Ok([name, ..rest])
    }
    _ -> Error("Malformed ALPN protocol list")
  }
}
