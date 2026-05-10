//// High-level HTTP helpers for existing Gun connections.
////
//// These helpers collect regular HTTP responses into `response.Response`.
//// Informational `1xx` responses are preserved in `Response.informational`.
//// Protocol messages for server push, upgrades, and WebSockets are rejected with
//// `InvalidMessage`; use the lower-level `gluegun/message` API for those flows.

import gleam/bit_array
import gleam/list
import gleam/result
import gluegun/connection.{type Timeout}
import gluegun/error
import gluegun/internal.{type Connection, type Stream}
import gluegun/message.{type Message}
import gluegun/request as low_request
import gluegun/response.{type Informational, type Response}

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

/// Send an HTTP request on an open connection and collect its full response.
pub fn request(
  connection: Connection,
  method: low_request.Method,
  path: String,
  headers: List(low_request.Header),
  body: BitArray,
  options: low_request.RequestOptions,
  timeout: Timeout,
) -> Result(Response, error.GluegunError) {
  use stream <- result.try(low_request.request(
    connection,
    method,
    path,
    headers,
    body,
    options,
  ))
  collect_stream(connection, stream, AwaitingResponse([]), timeout)
}

pub fn get(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  timeout: Timeout,
) -> Result(Response, error.GluegunError) {
  request(
    connection,
    low_request.Get,
    path,
    headers,
    <<>>,
    low_request.request_options(),
    timeout,
  )
}

pub fn post(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  body: BitArray,
  timeout: Timeout,
) -> Result(Response, error.GluegunError) {
  request(
    connection,
    low_request.Post,
    path,
    headers,
    body,
    low_request.request_options(),
    timeout,
  )
}

pub fn put(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  body: BitArray,
  timeout: Timeout,
) -> Result(Response, error.GluegunError) {
  request(
    connection,
    low_request.Put,
    path,
    headers,
    body,
    low_request.request_options(),
    timeout,
  )
}

pub fn patch(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  body: BitArray,
  timeout: Timeout,
) -> Result(Response, error.GluegunError) {
  request(
    connection,
    low_request.Patch,
    path,
    headers,
    body,
    low_request.request_options(),
    timeout,
  )
}

pub fn delete(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  timeout: Timeout,
) -> Result(Response, error.GluegunError) {
  request(
    connection,
    low_request.Delete,
    path,
    headers,
    <<>>,
    low_request.request_options(),
    timeout,
  )
}

pub fn head(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  timeout: Timeout,
) -> Result(Response, error.GluegunError) {
  request(
    connection,
    low_request.Head,
    path,
    headers,
    <<>>,
    low_request.request_options(),
    timeout,
  )
}

pub fn options(
  connection: Connection,
  path: String,
  headers: List(low_request.Header),
  timeout: Timeout,
) -> Result(Response, error.GluegunError) {
  request(
    connection,
    low_request.Options,
    path,
    headers,
    <<>>,
    low_request.request_options(),
    timeout,
  )
}

@internal
pub fn collect_messages(
  messages: List(Result(Message, error.GluegunError)),
) -> Result(Response, error.GluegunError) {
  collect_message_results(messages, AwaitingResponse([]))
}

fn collect_stream(
  connection: Connection,
  stream: Stream,
  collection: Collection,
  timeout: Timeout,
) -> Result(Response, error.GluegunError) {
  use awaited <- result.try(message.await(connection, stream, timeout))
  use next <- result.try(step(collection, awaited))
  case next {
    Done(response) -> Ok(response)
    Continue(collection) ->
      collect_stream(connection, stream, collection, timeout)
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
            message.Fin ->
              Ok(Done(build_response(status, headers, [], [], informational)))
            message.NoFin ->
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
          let chunks = list.append(chunks, [data])
          case fin {
            message.Fin ->
              Ok(
                Done(build_response(
                  status,
                  headers,
                  chunks,
                  trailers,
                  informational,
                )),
              )
            message.NoFin ->
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
  response.Response(
    status: status,
    headers: headers,
    body: bit_array.concat(chunks),
    trailers: trailers,
    informational: informational,
  )
}

fn invalid(message: String) -> Result(a, error.GluegunError) {
  Error(error.InvalidMessage(message))
}
