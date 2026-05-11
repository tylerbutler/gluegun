import gluegun
import gluegun/client
import gluegun/connection
import gluegun/request
import startest.{describe, it}
import startest/expect

pub fn main() -> Nil {
  startest.run(startest.default_config())
}

pub fn gluegun_tests() {
  describe("gluegun root facade", [
    it("returns the package name", fn() {
      gluegun.name()
      |> expect.to_equal("gluegun")
    }),
    it("builds a root request with default fields", fn() {
      gluegun.request(request.Get, "/")
      |> client.inspect_request
      |> expect.to_equal(client.RequestFields(
        method: request.Get,
        path: "/",
        headers: [],
        body: <<>>,
        options: request.options(),
        timeout: connection.Milliseconds(5000),
      ))
    }),
  ])
}
