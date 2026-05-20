//// High-level HTTP helpers for existing Gun connections.
////
//// These helpers collect regular HTTP/1.1 and HTTP/2 responses into
//// `response.Response`.
//// Informational `1xx` responses are preserved and can be inspected with
//// `response.informational`.
//// Protocol messages for server push, upgrades, and WebSockets are rejected with
//// `InvalidMessage`; use the lower-level `gluegun/message` API for those flows.
//// Full response bodies are collected in memory; use the lower-level APIs for
//// streaming or very large responses.

import gleam/bit_array
import gleam/list
import gleam/result
import gluegun/connection.{type Timeout, Milliseconds}
import gluegun/error
import gluegun/fin
import gluegun/internal.{type Connection, type Stream}
import gluegun/message.{type Message}
import gluegun/request as low_request
import gluegun/response.{type Informational, type Response}

/// A collected HTTP request command.
pub opaque type Request {
  Request(
    method: low_request.Method,
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
    method: low_request.Method,
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
  Done(Response)
}

/// Construct a collected HTTP request command.
pub fn new(method: low_request.Method, path: String) -> Request {
  Request(
    method: method,
    path: path,
    headers: [],
    body: <<>>,
    options: low_request.options(),
    timeout: Milliseconds(5000),
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
pub fn with_timeout(request: Request, timeout timeout: Timeout) -> Request {
  Request(..request, timeout: timeout)
}

/// Inspect a request command.
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

/// Send a collected HTTP request command on an open connection.
pub fn send(
  request: Request,
  connection connection: Connection,
) -> Result(Response, error.GluegunError) {
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
pub fn send_raw(
  connection: Connection,
  method: low_request.Method,
  path: String,
  headers: List(low_request.Header),
  body: BitArray,
  options: low_request.RequestOptions,
  timeout: Timeout,
) -> Result(Response, error.GluegunError) {
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
) -> Result(Response, error.GluegunError) {
  new(low_request.Get, path)
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
) -> Result(Response, error.GluegunError) {
  new(low_request.Post, path)
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
) -> Result(Response, error.GluegunError) {
  new(low_request.Put, path)
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
) -> Result(Response, error.GluegunError) {
  new(low_request.Patch, path)
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
) -> Result(Response, error.GluegunError) {
  new(low_request.Delete, path)
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
) -> Result(Response, error.GluegunError) {
  new(low_request.Head, path)
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
) -> Result(Response, error.GluegunError) {
  new(low_request.Options, path)
  |> add_headers(headers: headers)
  |> with_timeout(timeout: timeout)
  |> send(connection: connection)
}

@internal
pub fn collect_messages(
  messages: List(Result(Message, error.GluegunError)),
) -> Result(Response, error.GluegunError) {
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
    low_request.Method,
    String,
    List(low_request.Header),
    BitArray,
    low_request.RequestOptions,
  ) ->
    Result(Stream, error.GluegunError),
  await_fn: fn(Connection, Stream, Timeout) ->
    Result(Message, error.GluegunError),
) -> Result(Response, error.GluegunError) {
  request_with(
    connection,
    low_request.Get,
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
  method: low_request.Method,
  path: String,
  headers: List(low_request.Header),
  body: BitArray,
  options: low_request.RequestOptions,
  timeout: Timeout,
  request_fn: fn(
    Connection,
    low_request.Method,
    String,
    List(low_request.Header),
    BitArray,
    low_request.RequestOptions,
  ) ->
    Result(Stream, error.GluegunError),
  await_fn: fn(Connection, Stream, Timeout) ->
    Result(Message, error.GluegunError),
) -> Result(Response, error.GluegunError) {
  use stream <- result.try(request_fn(
    connection,
    method,
    path,
    headers,
    body,
    options,
  ))
  collect_stream_with(
    connection,
    stream,
    AwaitingResponse([]),
    timeout,
    await_fn,
  )
}

fn collect_stream_with(
  connection: Connection,
  stream: Stream,
  collection: Collection,
  timeout: Timeout,
  await_fn: fn(Connection, Stream, Timeout) ->
    Result(Message, error.GluegunError),
) -> Result(Response, error.GluegunError) {
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
) -> Result(Response, error.GluegunError) {
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
  case message {
    message.Inform(status, headers) ->
      case collection {
        AwaitingResponse(informational) ->
          Ok(
            Continue(
              AwaitingResponse(list.append(informational, [#(status, headers)])),
            ),
          )
        Collecting(_, _, _, _, _) ->
          invalid(
            "HTTP helper received informational response after final response",
          )
      }

    message.Response(fin, status, headers) ->
      case collection {
        AwaitingResponse(informational) ->
          case fin {
            fin.Fin ->
              Ok(Done(build_response(status, headers, [], [], informational)))
            fin.NoFin ->
              Ok(Continue(Collecting(status, headers, [], [], informational)))
          }
        Collecting(_, _, _, _, _) ->
          invalid("HTTP helper received duplicate response")
      }

    message.Data(fin, data) ->
      case collection {
        AwaitingResponse(_) ->
          invalid("HTTP helper received body before response")
        Collecting(status, headers, chunks, trailers, informational) -> {
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
      }

    message.Trailers(headers) ->
      case collection {
        AwaitingResponse(_) ->
          invalid("HTTP helper received trailers before response")
        Collecting(status, response_headers, chunks, trailers, informational) ->
          Ok(
            Done(build_response(
              status,
              response_headers,
              chunks,
              list.append(trailers, headers),
              informational,
            )),
          )
      }

    message.Push(_, _, _, _) -> invalid("HTTP helper received push message")
    message.Upgrade(_, _) -> invalid("HTTP helper received upgrade message")
    message.WebSocket(_) -> invalid("HTTP helper received websocket message")
  }
}

fn finalize_end(collection: Collection) -> Result(Response, error.GluegunError) {
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
) -> Response {
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
