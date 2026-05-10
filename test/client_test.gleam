import gleam/dynamic
import gleeunit/should
import gluegun/client
import gluegun/connection
import gluegun/error
import gluegun/fin
import gluegun/internal
import gluegun/message
import gluegun/request
import gluegun/response

pub fn client_request_builder_sets_fields_test() {
  client.new(request.Get, "/")
  |> client.with_header("accept", "application/json")
  |> client.with_body(<<"":utf8>>)
  |> client.with_timeout(connection.Milliseconds(1000))
  |> client.inspect_request
  |> should.equal(client.RequestFields(
    method: request.Get,
    path: "/",
    headers: [#("accept", "application/json")],
    body: <<"":utf8>>,
    options: request.options(),
    timeout: connection.Milliseconds(1000),
  ))
}

pub fn client_collects_single_final_body_test() {
  client.collect_messages([
    Ok(message.Response(fin.NoFin, 200, [#("content-type", "text/plain")])),
    Ok(message.Data(fin.Fin, <<"hello":utf8>>)),
  ])
  |> should.equal(
    Ok(
      response.new(
        status: 200,
        headers: [#("content-type", "text/plain")],
        body: <<"hello":utf8>>,
        trailers: [],
      ),
    ),
  )
}

pub fn client_collects_multiple_data_chunks_in_order_test() {
  let assert Ok(res) =
    client.collect_messages([
      Ok(message.Response(fin.NoFin, 200, [])),
      Ok(message.Data(fin.NoFin, <<"chunk-1|":utf8>>)),
      Ok(message.Data(fin.NoFin, <<"chunk-2|":utf8>>)),
      Ok(message.Data(fin.NoFin, <<"chunk-3|":utf8>>)),
      Ok(message.Data(fin.NoFin, <<"chunk-4|":utf8>>)),
      Ok(message.Data(fin.Fin, <<"chunk-5":utf8>>)),
    ])

  res
  |> response.body
  |> should.equal(<<"chunk-1|chunk-2|chunk-3|chunk-4|chunk-5":utf8>>)
}

pub fn client_preserves_trailers_test() {
  let assert Ok(res) =
    client.collect_messages([
      Ok(message.Response(fin.NoFin, 200, [])),
      Ok(message.Data(fin.NoFin, <<"hello":utf8>>)),
      Ok(message.Trailers([#("expires", "soon")])),
    ])

  res
  |> response.trailers
  |> should.equal([#("expires", "soon")])
}

pub fn client_preserves_informational_responses_test() {
  let assert Ok(res) =
    client.collect_messages([
      Ok(message.Inform(103, [#("link", "</style.css>; rel=preload")])),
      Ok(message.Response(fin.Fin, 204, [#("server", "gun")])),
    ])

  res
  |> response.informational
  |> should.equal([#(103, [#("link", "</style.css>; rel=preload")])])
}

pub fn client_rejects_informational_after_final_response_test() {
  client.collect_messages([
    Ok(message.Response(fin.NoFin, 200, [])),
    Ok(message.Inform(103, [])),
  ])
  |> should.equal(
    Error(error.InvalidMessage(
      "HTTP helper received informational response after final response",
    )),
  )
}

pub fn client_rejects_push_upgrade_and_websocket_test() {
  let stream = internal.stream(dynamic.string("stream-1"))

  client.collect_messages([
    Ok(message.Push(stream, request.Get, "/pushed", [])),
  ])
  |> should.equal(
    Error(error.InvalidMessage("HTTP helper received push message")),
  )

  client.collect_messages([Ok(message.Upgrade(["websocket"], []))])
  |> should.equal(
    Error(error.InvalidMessage("HTTP helper received upgrade message")),
  )

  client.collect_messages([Ok(message.WebSocket(message.Text("hello")))])
  |> should.equal(
    Error(error.InvalidMessage("HTTP helper received websocket message")),
  )
}

pub fn client_body_before_response_is_invalid_test() {
  client.collect_messages([Ok(message.Data(fin.Fin, <<"oops":utf8>>))])
  |> should.equal(
    Error(error.InvalidMessage("HTTP helper received body before response")),
  )
}

pub fn client_duplicate_response_is_invalid_test() {
  client.collect_messages([
    Ok(message.Response(fin.NoFin, 200, [])),
    Ok(message.Response(fin.Fin, 204, [])),
  ])
  |> should.equal(
    Error(error.InvalidMessage("HTTP helper received duplicate response")),
  )
}

pub fn client_trailers_before_response_is_invalid_test() {
  client.collect_messages([Ok(message.Trailers([#("expires", "soon")]))])
  |> should.equal(
    Error(error.InvalidMessage("HTTP helper received trailers before response")),
  )
}

pub fn client_propagates_timeout_and_connection_down_test() {
  client.collect_messages([Error(error.Timeout)])
  |> should.equal(Error(error.Timeout))

  client.collect_messages([Error(error.ConnectionDown("closed"))])
  |> should.equal(Error(error.ConnectionDown("closed")))
}

pub fn client_body_text_decodes_utf8_test() {
  response.new(status: 200, headers: [], body: <<"héllo":utf8>>, trailers: [])
  |> response.body_text
  |> should.equal(Ok("héllo"))
}

pub fn client_body_text_rejects_invalid_utf8_test() {
  response.new(status: 200, headers: [], body: <<255>>, trailers: [])
  |> response.body_text
  |> should.equal(Error(error.DecodeError("Response body is not valid UTF-8")))
}
