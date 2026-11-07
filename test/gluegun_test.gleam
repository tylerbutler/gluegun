import gluegun
import gluegun/client
import gluegun/connection
import gluegun/internal
import gluegun/request
import gluegun/websocket
import unitest

pub fn main() -> Nil {
  unitest.main()
}

pub fn builds_a_root_request_with_default_fields_test() -> Nil {
  let actual_1 = {
    gluegun.new_request(request.Get, "/")
    |> client.inspect_request
  }
  let expected_1 =
    client.RequestFields(
      method: request.Get,
      path: "/",
      headers: [],
      body: <<>>,
      options: request.options(),
      timeout: connection.default_timeout(),
    )
  let assert #(True, _, _) = #(actual_1 == expected_1, actual_1, expected_1)
  Nil
}

pub fn exposes_root_websocket_options_test() -> Nil {
  let actual_2 = {
    gluegun.websocket_options()
    |> websocket.options_timeout
  }
  let expected_2 = connection.default_timeout()
  let assert #(True, _, _) = #(actual_2 == expected_2, actual_2, expected_2)
  Nil
}

pub fn exposes_the_minimal_common_path_root_helpers_test() -> Nil {
  let actual_3 = compile_common_path_facade(False)
  let expected_3 = Nil
  let assert #(True, _, _) = #(actual_3 == expected_3, actual_3, expected_3)
  Nil
}

pub fn exposes_public_handle_types_from_non_internal_modules_test() -> Nil {
  let actual_4 = compile_public_handle_types(False)
  let expected_4 = Nil
  let assert #(True, _, _) = #(actual_4 == expected_4, actual_4, expected_4)
  Nil
}

fn compile_common_path_facade(should_run: Bool) -> Nil {
  case should_run {
    True -> {
      let assert Ok(open_connection) =
        gluegun.open(
          gluegun.connection_options(),
          host: "localhost",
          port: 8080,
        )
      let assert Ok(_protocol) =
        gluegun.await_up(open_connection, connection.default_timeout())
      let request = gluegun.new_request(request.Get, "/")
      let assert Ok(response) =
        gluegun.send(request, connection: open_connection)
      let assert Ok(_body) = gluegun.body_text(response)
      let assert Ok(_socket) =
        gluegun.websocket_connect(
          host: "localhost",
          port: 8080,
          path: "/echo",
          options: gluegun.websocket_options(),
        )
      Nil
    }
    False -> Nil
  }
}

fn compile_public_handle_types(should_run: Bool) -> Nil {
  case should_run {
    True -> {
      let connection = invalid_connection()
      let stream = stream_ref()
      let _ = accept_connection(connection)
      let _ = accept_stream(stream)
      Nil
    }
    False -> Nil
  }
}

fn accept_connection(_connection: connection.Connection) -> Nil {
  Nil
}

fn accept_stream(_stream: request.Stream) -> Nil {
  Nil
}

@external(erlang, "gluegun_ffi_test", "invalid_connection")
fn invalid_connection() -> internal.Connection

@external(erlang, "gluegun_ffi_test", "stream_ref")
fn stream_ref() -> internal.Stream
