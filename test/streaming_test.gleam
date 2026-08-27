import gluegun/error
import gluegun/fin
import gluegun/internal
import gluegun/request
import startest
import startest/expect
import startest/test_tree

pub fn streaming_tests() -> test_tree.TestTree {
  startest.describe("streaming requests", [
    startest.describe("request FFI shapes", [
      startest.it("normalizes streaming request headers", fn() {
        let assert Ok(_stream) =
          request.start_stream(
            current_connection(),
            request.Post,
            "/upload",
            [#("Content-Type", "text/plain")],
            request.options()
              |> request.add_headers([#("X-Trace", "abc")]),
          )

        capture_stream_headers()
        |> expect.to_equal(
          Ok(
            #("POST", "/upload", [
              #("content-type", "text/plain"),
              #("x-trace", "abc"),
            ]),
          ),
        )
      }),
      startest.it("returns an opaque stream for started streams", fn() {
        let assert Ok(first) =
          request.start_stream(
            current_connection(),
            request.Post,
            "/upload",
            [],
            request.options(),
          )
        let assert Ok(second) =
          request.start_stream(
            current_connection(),
            request.Post,
            "/upload",
            [],
            request.options(),
          )
        let _ = capture_stream_headers()
        let _ = capture_stream_headers()

        { first == second }
        |> expect.to_be_false
      }),
      startest.it("surfaces request errors instead of stream handles", fn() {
        request.request(
          invalid_connection(),
          request.Post,
          "/upload",
          [],
          <<>>,
          request.options(),
        )
        |> expect.to_equal(Error(error.ErlangError("Error(FunctionClause)")))
      }),
      startest.it("encodes fin values for streaming data", fn() {
        capture_data_fin(fin.Fin, <<"chunk":utf8>>)
        |> expect.to_equal(Ok("fin"))

        capture_data_fin(fin.NoFin, <<"chunk":utf8>>)
        |> expect.to_equal(Ok("nofin"))
      }),
    ]),
    startest.describe("stream control", [
      startest.it("cancels streams on an open connection", fn() {
        request.cancel(current_connection(), stream_ref())
        |> expect.to_equal(Ok(Nil))
      }),
      startest.it("surfaces cancel errors", fn() {
        request.cancel(invalid_connection(), stream_ref())
        |> expect.to_equal(Error(error.StreamError("Error(FunctionClause)")))
      }),
      startest.it("encodes update_flow increments", fn() {
        capture_update_flow(1234)
        |> expect.to_equal(Ok(1234))
      }),
      startest.it("surfaces update_flow errors", fn() {
        request.update_flow(invalid_connection(), stream_ref(), 1)
        |> expect.to_equal(Error(error.StreamError("Error(FunctionClause)")))
      }),
      startest.it("rejects zero update_flow increments", fn() {
        request.update_flow(current_connection(), stream_ref(), 0)
        |> expect.to_equal(
          Error(error.InvalidOptions("flow-control increment must be positive")),
        )
      }),
      startest.it("rejects negative update_flow increments", fn() {
        request.update_flow(current_connection(), stream_ref(), -1)
        |> expect.to_equal(
          Error(error.InvalidOptions("flow-control increment must be positive")),
        )
      }),
    ]),
  ])
}

@external(erlang, "gluegun_ffi_test", "current_connection")
fn current_connection() -> internal.Connection

@external(erlang, "gluegun_ffi_test", "invalid_connection")
fn invalid_connection() -> internal.Connection

@external(erlang, "gluegun_ffi_test", "stream_ref")
fn stream_ref() -> internal.Stream

@external(erlang, "gluegun_ffi_test", "capture_stream_headers")
fn capture_stream_headers() -> Result(
  #(String, String, List(#(String, String))),
  error.GluegunError,
)

@external(erlang, "gluegun_ffi_test", "capture_data_fin")
fn capture_data_fin(
  fin: fin.Fin,
  data: BitArray,
) -> Result(String, error.GluegunError)

@external(erlang, "gluegun_ffi_test", "capture_update_flow")
fn capture_update_flow(increment: Int) -> Result(Int, error.GluegunError)
