//// High-level HTTP helpers for existing Gun connections.
////
//// These helpers collect a full HTTP/1.1 or HTTP/2 response — status,
//// headers, body, trailers, and any informational `1xx` responses — into a
//// `response.Response(BitArray)`. Its `response` field is a standard
//// `gleam/http/response.Response(BitArray)`. The body is held fully in memory;
//// use the lower-level `gluegun/request` and `gluegun/message` APIs for
//// streaming or very large responses.
////
//// Protocol messages for server push, upgrades, and WebSockets are rejected
//// with `InvalidMessage`. Use the lower-level `gluegun/message` API for
//// those flows.
////
//// If collection fails, these helpers attempt to cancel the failed stream
//// and drain its queued messages, then return the original error. They keep
//// other streams and the connection open. Cancellation is asynchronous:
//// messages in transit can arrive after the drain. For strict mailbox
//// isolation, use the low-level API in a separate receiving process.

import gleam/bit_array
import gleam/http
import gleam/http/response as http_response
import gleam/list
import gleam/result
import gluegun/connection.{type Connection, type Timeout}
import gluegun/error
import gluegun/fin
import gluegun/message.{type Message}
import gluegun/request as low_request
import gluegun/response.{type Informational, type Response}

/// A connection-bound request: method, path, headers, body, options, and timeout.
///
/// The connection supplied to `send` determines the scheme, host, and port.
/// Supply a request target such as `/items?page=2`, not a full URL. Gluegun
/// sends the path and query as supplied; it does not percent-encode them.
/// The body must contain whole bytes and need not be UTF-8.
///
/// This custom type avoids duplicating the connection's destination fields.
/// It does not accept or convert standard `gleam/http/request.Request` values.
pub opaque type Request {
  Request(
    method: http.Method,
    path: String,
    headers: List(low_request.Header),
    body: BitArray,
    options: low_request.RequestOptions,
    timeout: Timeout,
  )
}

/// Inspectable request fields for deterministic tests.
@internal
pub type RequestFields {
  RequestFields(
    method: http.Method,
    path: String,
    headers: List(low_request.Header),
    body: BitArray,
    options: low_request.RequestOptions,
    timeout: Timeout,
  )
}

type Collection {
  AwaitingResponse(informational: List(Informational))
  Collecting(
    status: Int,
    headers: List(low_request.Header),
    chunks: List(BitArray),
    trailers: List(low_request.Header),
    informational: List(Informational),
  )
}

type Step {
  Continue(Collection)
  Done(Response(BitArray))
}

/// Start a new `Request` builder with the given method and path.
pub fn new(method: http.Method, path: String) -> Request {
  Request(
    method: method,
    path: path,
    headers: [],
    body: <<>>,
    options: low_request.options(),
    timeout: connection.default_timeout(),
  )
}

/// Append a single request header.
pub fn with_header(
  request: Request,
  name name: String,
  value value: String,
) -> Request {
  Request(..request, headers: list.append(request.headers, [#(name, value)]))
}

/// Append request headers.
pub fn add_headers(
  request: Request,
  headers headers: List(low_request.Header),
) -> Request {
  Request(..request, headers: list.append(request.headers, headers))
}

/// Replace request headers.
pub fn with_headers(
  request: Request,
  headers headers: List(low_request.Header),
) -> Request {
  Request(..request, headers: headers)
}

/// Replace the request body.
pub fn with_body(request: Request, body body: BitArray) -> Request {
  Request(..request, body: body)
}

/// Replace low-level request options.
pub fn with_options(
  request: Request,
  options options: low_request.RequestOptions,
) -> Request {
  Request(..request, options: options)
}

/// Replace the request timeout.
///
/// This bounds each response-message wait, not the complete exchange.
pub fn with_timeout(request: Request, timeout timeout: Timeout) -> Request {
  Request(..request, timeout: timeout)
}

/// Inspect a built `Request`. Intended for deterministic tests.
@internal
pub fn inspect_request(request: Request) -> RequestFields {
  RequestFields(
    method: request.method,
    path: request.path,
    headers: request.headers,
    body: request.body,
    options: request.options,
    timeout: request.timeout,
  )
}

/// Send a built `Request` on an open connection and collect the response.
pub fn send(
  request: Request,
  connection connection: Connection,
) -> Result(Response(BitArray), error.GluegunError) {
  send_raw(
    connection,
    request.method,
    request.path,
    request.headers,
    request.body,
    request.options,
    request.timeout,
  )
}

/// Send an HTTP request on an open connection and collect its full response.
@internal
pub fn send_raw(
  connection: Connection,
  method: http.Method,
  path: String,
  headers: List(low_request.Header),
  body: BitArray,
  options: low_request.RequestOptions,
  timeout: Timeout,
) -> Result(Response(BitArray), error.GluegunError) {
  request_with(
    connection,
    method,
    path,
    headers,
    body,
    options,
    timeout,
    low_request.request,
    message.await,
  )
}

/// Send GET on an open connection and collect the full response.
pub fn get(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  timeout: Timeout,
) -> Result(Response(BitArray), error.GluegunError) {
  new(http.Get, path)
  |> add_headers(headers: headers)
  |> with_timeout(timeout: timeout)
  |> send(connection: connection)
}

/// Send POST on an open connection and collect the full response.
pub fn post(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  body: BitArray,
  timeout: Timeout,
) -> Result(Response(BitArray), error.GluegunError) {
  new(http.Post, path)
  |> add_headers(headers: headers)
  |> with_body(body: body)
  |> with_timeout(timeout: timeout)
  |> send(connection: connection)
}

/// Send PUT on an open connection and collect the full response.
pub fn put(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  body: BitArray,
  timeout: Timeout,
) -> Result(Response(BitArray), error.GluegunError) {
  new(http.Put, path)
  |> add_headers(headers: headers)
  |> with_body(body: body)
  |> with_timeout(timeout: timeout)
  |> send(connection: connection)
}

/// Send PATCH on an open connection and collect the full response.
pub fn patch(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  body: BitArray,
  timeout: Timeout,
) -> Result(Response(BitArray), error.GluegunError) {
  new(http.Patch, path)
  |> add_headers(headers: headers)
  |> with_body(body: body)
  |> with_timeout(timeout: timeout)
  |> send(connection: connection)
}

/// Send DELETE on an open connection and collect the full response.
pub fn delete(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  timeout: Timeout,
) -> Result(Response(BitArray), error.GluegunError) {
  new(http.Delete, path)
  |> add_headers(headers: headers)
  |> with_timeout(timeout: timeout)
  |> send(connection: connection)
}

/// Send HEAD on an open connection and collect the full response.
pub fn head(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  timeout: Timeout,
) -> Result(Response(BitArray), error.GluegunError) {
  new(http.Head, path)
  |> add_headers(headers: headers)
  |> with_timeout(timeout: timeout)
  |> send(connection: connection)
}

/// Send OPTIONS on an open connection and collect the full response.
pub fn request_options(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  timeout: Timeout,
) -> Result(Response(BitArray), error.GluegunError) {
  new(http.Options, path)
  |> add_headers(headers: headers)
  |> with_timeout(timeout: timeout)
  |> send(connection: connection)
}

@internal
pub fn collect_messages(
  messages: List(Result(Message, error.GluegunError)),
) -> Result(Response(BitArray), error.GluegunError) {
  collect_message_results(messages, AwaitingResponse([]))
}

@internal
pub fn get_with(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  timeout: Timeout,
  request_fn: fn(
    Connection,
    http.Method,
    String,
    List(low_request.Header),
    BitArray,
    low_request.RequestOptions,
  ) ->
    Result(low_request.Stream, error.GluegunError),
  await_fn: fn(Connection, low_request.Stream, Timeout) ->
    Result(Message, error.GluegunError),
) -> Result(Response(BitArray), error.GluegunError) {
  request_with(
    connection,
    http.Get,
    path,
    headers,
    <<>>,
    low_request.options(),
    timeout,
    request_fn,
    await_fn,
  )
}

@internal
pub fn request_with(
  connection: Connection,
  method: http.Method,
  path: String,
  headers: List(low_request.Header),
  body: BitArray,
  options: low_request.RequestOptions,
  timeout: Timeout,
  request_fn: fn(
    Connection,
    http.Method,
    String,
    List(low_request.Header),
    BitArray,
    low_request.RequestOptions,
  ) ->
    Result(low_request.Stream, error.GluegunError),
  await_fn: fn(Connection, low_request.Stream, Timeout) ->
    Result(Message, error.GluegunError),
) -> Result(Response(BitArray), error.GluegunError) {
  use stream <- result.try(request_fn(
    connection,
    method,
    path,
    headers,
    body,
    options,
  ))
  case
    collect_stream_with(
      connection,
      stream,
      AwaitingResponse([]),
      timeout,
      await_fn,
    )
  {
    Ok(response) -> Ok(response)
    Error(reason) -> {
      let _ = cleanup_stream(connection, stream)
      Error(reason)
    }
  }
}

@external(erlang, "gluegun_ffi", "cleanup_stream")
fn cleanup_stream(
  connection: Connection,
  stream: low_request.Stream,
) -> Result(Nil, error.GluegunError)

fn collect_stream_with(
  connection: Connection,
  stream: low_request.Stream,
  collection: Collection,
  timeout: Timeout,
  await_fn: fn(Connection, low_request.Stream, Timeout) ->
    Result(Message, error.GluegunError),
) -> Result(Response(BitArray), error.GluegunError) {
  use awaited <- result.try(await_fn(connection, stream, timeout))
  use next <- result.try(step(collection, awaited))
  case next {
    Done(response) -> Ok(response)
    Continue(collection) ->
      collect_stream_with(connection, stream, collection, timeout, await_fn)
  }
}

fn collect_message_results(
  messages: List(Result(Message, error.GluegunError)),
  collection: Collection,
) -> Result(Response(BitArray), error.GluegunError) {
  case messages {
    [] -> finalize_end(collection)
    [message_result, ..rest] -> {
      use awaited <- result.try(message_result)
      use next <- result.try(step(collection, awaited))
      case next {
        Done(response) -> Ok(response)
        Continue(collection) -> collect_message_results(rest, collection)
      }
    }
  }
}

fn step(
  collection: Collection,
  message: Message,
) -> Result(Step, error.GluegunError) {
  case collection {
    AwaitingResponse(informational) -> handle_awaiting(informational, message)
    Collecting(status, headers, chunks, trailers, informational) ->
      handle_collecting(
        status,
        headers,
        chunks,
        trailers,
        informational,
        message,
      )
  }
}

fn handle_awaiting(
  informational: List(Informational),
  message: Message,
) -> Result(Step, error.GluegunError) {
  case message {
    message.Inform(status, headers) ->
      Ok(
        Continue(
          AwaitingResponse(
            list.append(informational, [
              http_response.Response(
                status: status,
                headers: headers,
                body: Nil,
              ),
            ]),
          ),
        ),
      )
    message.Response(fin, status, headers) ->
      case fin {
        fin.Fin ->
          Ok(Done(build_response(status, headers, [], [], informational)))
        fin.NoFin ->
          Ok(Continue(Collecting(status, headers, [], [], informational)))
      }
    message.Data(_, _) -> invalid("HTTP helper received body before response")
    message.Trailers(_) ->
      invalid("HTTP helper received trailers before response")
    message.Push(_, _, _, _) -> invalid("HTTP helper received push message")
    message.Upgrade(_, _) -> invalid("HTTP helper received upgrade message")
    message.WebSocket(_) -> invalid("HTTP helper received websocket message")
  }
}

fn handle_collecting(
  status: Int,
  headers: List(low_request.Header),
  chunks: List(BitArray),
  trailers: List(low_request.Header),
  informational: List(Informational),
  message: Message,
) -> Result(Step, error.GluegunError) {
  case message {
    message.Inform(_, _) ->
      invalid(
        "HTTP helper received informational response after final response",
      )
    message.Response(_, _, _) ->
      invalid("HTTP helper received duplicate response")
    message.Data(fin, data) -> {
      let chunks = [data, ..chunks]
      case fin {
        fin.Fin ->
          Ok(
            Done(build_response(
              status,
              headers,
              chunks,
              trailers,
              informational,
            )),
          )
        fin.NoFin ->
          Ok(
            Continue(Collecting(
              status,
              headers,
              chunks,
              trailers,
              informational,
            )),
          )
      }
    }
    message.Trailers(trailer_headers) ->
      Ok(
        Done(build_response(
          status,
          headers,
          chunks,
          list.append(trailers, trailer_headers),
          informational,
        )),
      )
    message.Push(_, _, _, _) -> invalid("HTTP helper received push message")
    message.Upgrade(_, _) -> invalid("HTTP helper received upgrade message")
    message.WebSocket(_) -> invalid("HTTP helper received websocket message")
  }
}

fn finalize_end(
  collection: Collection,
) -> Result(Response(BitArray), error.GluegunError) {
  case collection {
    AwaitingResponse(_) -> invalid("HTTP helper stream ended before response")
    Collecting(_, _, _, _, _) ->
      invalid("HTTP helper stream ended before final message")
  }
}

fn build_response(
  status: Int,
  headers: List(low_request.Header),
  chunks: List(BitArray),
  trailers: List(low_request.Header),
  informational: List(Informational),
) -> Response(BitArray) {
  response.new(
    status: status,
    headers: headers,
    body: bit_array.concat(list.reverse(chunks)),
    trailers: trailers,
  )
  |> response.with_informational(informational: informational)
}

fn invalid(message: String) -> Result(a, error.GluegunError) {
  Error(error.InvalidMessage(message))
}
