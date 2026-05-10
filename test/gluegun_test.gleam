import gleeunit
import gleeunit/should
import gluegun
import gluegun/client
import gluegun/connection
import gluegun/request

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn name_test() {
  gluegun.name()
  |> should.equal("gluegun")
}

pub fn root_request_builder_test() {
  gluegun.request(request.Get, "/")
  |> client.inspect_request
  |> should.equal(client.RequestFields(
    method: request.Get,
    path: "/",
    headers: [],
    body: <<>>,
    options: request.options(),
    timeout: connection.Milliseconds(5000),
  ))
}
