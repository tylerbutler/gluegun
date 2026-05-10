import gleam/dynamic
import gleam/option.{None, Some}
import gleeunit/should
import gluegun/connection
import gluegun/error
import gluegun/internal
import gluegun/message
import gluegun/request
import gluegun/response
import gluegun/types

pub fn default_connect_options_test() {
  let options = connection.connect_options()

  options
  |> connection.transport
  |> should.equal(connection.Auto)

  options
  |> connection.protocols
  |> should.equal(None)
}

pub fn protocol_ordering_test() {
  connection.connect_options()
  |> connection.with_protocols([connection.Http2, connection.Http1])
  |> connection.protocols
  |> should.equal(Some([connection.Http2, connection.Http1]))
}

pub fn method_conversion_test() {
  request.method_to_string(types.Get)
  |> should.equal("GET")

  request.method_to_string(types.Post)
  |> should.equal("POST")

  request.method_to_string(types.Custom("PROPFIND"))
  |> should.equal("PROPFIND")
}

pub fn header_normalization_test() {
  [#("Content-Type", "text/plain"), #("X-Request-ID", "ABC123")]
  |> request.normalize_headers
  |> should.equal([#("content-type", "text/plain"), #("x-request-id", "ABC123")])
}

pub fn response_construction_test() {
  let res =
    response.new(
      status: 200,
      headers: [#("content-type", "text/plain")],
      body: <<"hello":utf8>>,
      trailers: [#("expires", "soon")],
    )

  res.status
  |> should.equal(200)

  res.headers
  |> should.equal([#("content-type", "text/plain")])

  res.body
  |> should.equal(<<"hello":utf8>>)

  res.trailers
  |> should.equal([#("expires", "soon")])
}

pub fn message_construction_test() {
  message.Response(message.NoFin, 204, [#("server", "gun")])
  |> should.equal(message.Response(message.NoFin, 204, [#("server", "gun")]))
}

pub fn message_decode_response_test() {
  let value =
    dynamic.properties([
      #(dynamic.string("type"), dynamic.string("response")),
      #(dynamic.string("fin"), dynamic.bool(False)),
      #(dynamic.string("status"), dynamic.int(201)),
      #(
        dynamic.string("headers"),
        dynamic.list([
          dynamic.array([
            dynamic.string("Content-Type"),
            dynamic.string("text/plain"),
          ]),
        ]),
      ),
    ])

  message.decode(value)
  |> should.equal(
    Ok(message.Response(message.NoFin, 201, [#("content-type", "text/plain")])),
  )
}

pub fn message_decode_data_test() {
  let value =
    dynamic.properties([
      #(dynamic.string("type"), dynamic.string("data")),
      #(dynamic.string("fin"), dynamic.bool(True)),
      #(dynamic.string("data"), dynamic.bit_array(<<"ok":utf8>>)),
    ])

  message.decode(value)
  |> should.equal(Ok(message.Data(message.Fin, <<"ok":utf8>>)))
}

pub fn message_decode_inform_test() {
  let value =
    dynamic.properties([
      #(dynamic.string("type"), dynamic.string("inform")),
      #(dynamic.string("status"), dynamic.int(102)),
      #(
        dynamic.string("headers"),
        dynamic.list([
          dynamic.array([dynamic.string("Server"), dynamic.string("gun")]),
        ]),
      ),
    ])

  message.decode(value)
  |> should.equal(Ok(message.Inform(102, [#("server", "gun")])))
}

pub fn message_decode_trailers_test() {
  let value =
    dynamic.properties([
      #(dynamic.string("type"), dynamic.string("trailers")),
      #(
        dynamic.string("headers"),
        dynamic.list([
          dynamic.array([dynamic.string("Expires"), dynamic.string("soon")]),
        ]),
      ),
    ])

  message.decode(value)
  |> should.equal(Ok(message.Trailers([#("expires", "soon")])))
}

pub fn message_decode_upgrade_test() {
  let value =
    dynamic.properties([
      #(dynamic.string("type"), dynamic.string("upgrade")),
      #(
        dynamic.string("protocols"),
        dynamic.list([dynamic.string("websocket")]),
      ),
      #(
        dynamic.string("headers"),
        dynamic.list([
          dynamic.array([
            dynamic.string("Connection"),
            dynamic.string("upgrade"),
          ]),
        ]),
      ),
    ])

  message.decode(value)
  |> should.equal(
    Ok(message.Upgrade(["websocket"], [#("connection", "upgrade")])),
  )
}

pub fn message_decode_push_test() {
  let stream = dynamic.string("stream-1")
  let value =
    dynamic.properties([
      #(dynamic.string("type"), dynamic.string("push")),
      #(dynamic.string("stream"), stream),
      #(dynamic.string("method"), dynamic.string("POST")),
      #(dynamic.string("uri"), dynamic.string("/assets/app.css")),
      #(
        dynamic.string("headers"),
        dynamic.list([
          dynamic.array([dynamic.string("Accept"), dynamic.string("text/css")]),
        ]),
      ),
    ])

  message.decode(value)
  |> should.equal(
    Ok(
      message.Push(internal.stream(stream), types.Post, "/assets/app.css", [
        #("accept", "text/css"),
      ]),
    ),
  )
}

pub fn message_decode_push_preserves_custom_method_case_test() {
  let stream = dynamic.string("stream-1")
  let value =
    dynamic.properties([
      #(dynamic.string("type"), dynamic.string("push")),
      #(dynamic.string("stream"), stream),
      #(dynamic.string("method"), dynamic.string("PropFind")),
      #(dynamic.string("uri"), dynamic.string("/collection")),
      #(dynamic.string("headers"), dynamic.list([])),
    ])

  message.decode(value)
  |> should.equal(
    Ok(
      message.Push(
        internal.stream(stream),
        types.Custom("PropFind"),
        "/collection",
        [],
      ),
    ),
  )
}

pub fn message_decode_push_matches_known_methods_case_insensitively_test() {
  let stream = dynamic.string("stream-1")
  let value =
    dynamic.properties([
      #(dynamic.string("type"), dynamic.string("push")),
      #(dynamic.string("stream"), stream),
      #(dynamic.string("method"), dynamic.string("get")),
      #(dynamic.string("uri"), dynamic.string("/")),
      #(dynamic.string("headers"), dynamic.list([])),
    ])

  message.decode(value)
  |> should.equal(Ok(message.Push(internal.stream(stream), types.Get, "/", [])))
}

pub fn message_decode_unknown_message_tag_fails_test() {
  let value =
    dynamic.properties([
      #(dynamic.string("type"), dynamic.string("mystery")),
    ])

  message.decode(value)
  |> should.equal(Error(error.DecodeError("Invalid Gun message")))
}

pub fn message_decode_unknown_websocket_frame_tag_fails_test() {
  let value =
    dynamic.properties([
      #(dynamic.string("type"), dynamic.string("websocket")),
      #(
        dynamic.string("frame"),
        dynamic.properties([
          #(dynamic.string("type"), dynamic.string("mystery")),
        ]),
      ),
    ])

  message.decode(value)
  |> should.equal(Error(error.DecodeError("Invalid Gun message")))
}

pub fn message_decode_websocket_test() {
  let value =
    dynamic.properties([
      #(dynamic.string("type"), dynamic.string("websocket")),
      #(
        dynamic.string("frame"),
        dynamic.properties([
          #(dynamic.string("type"), dynamic.string("text")),
          #(dynamic.string("data"), dynamic.string("hello")),
        ]),
      ),
    ])

  message.decode(value)
  |> should.equal(Ok(message.WebSocket(message.Text("hello"))))
}
