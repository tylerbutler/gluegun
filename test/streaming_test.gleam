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
    startest.describe("request injection guards", [
      startest.it("rejects a CRLF-split request path", fn() {
        request.request(
          current_connection(),
          request.Get,
          "/upload HTTP/1.1\r\nX-Injected: evil",
          [],
          <<>>,
          request.options(),
        )
        |> expect.to_equal(Error(error.InvalidOptions("Request(InvalidPath)")))
      }),
      startest.it("rejects a bare NUL byte in the request path", fn() {
        request.request(
          current_connection(),
          request.Get,
          "/upload\u{0000}.txt",
          [],
          <<>>,
          request.options(),
        )
        |> expect.to_equal(Error(error.InvalidOptions("Request(InvalidPath)")))
      }),
      startest.it("rejects a literal space in the request path", fn() {
        request.request(
          current_connection(),
          request.Get,
          "/upload HTTP/1.1",
          [],
          <<>>,
          request.options(),
        )
        |> expect.to_equal(Error(error.InvalidOptions("Request(InvalidPath)")))
      }),
      startest.it("rejects an empty request path", fn() {
        request.request(
          current_connection(),
          request.Get,
          "",
          [],
          <<>>,
          request.options(),
        )
        |> expect.to_equal(Error(error.InvalidOptions("Request(InvalidPath)")))
      }),
      startest.it("rejects a CRLF-injected header value", fn() {
        request.request(
          current_connection(),
          request.Post,
          "/upload",
          [#("X-Trace", "abc\r\nX-Injected: evil")],
          <<>>,
          request.options(),
        )
        |> expect.to_equal(
          Error(error.InvalidOptions("Request(InvalidHeaderValue)")),
        )
      }),
      startest.it("rejects a NUL byte in a header value", fn() {
        request.request(
          current_connection(),
          request.Post,
          "/upload",
          [#("X-Trace", "abc\u{0000}def")],
          <<>>,
          request.options(),
        )
        |> expect.to_equal(
          Error(error.InvalidOptions("Request(InvalidHeaderValue)")),
        )
      }),
      startest.it("rejects a vertical-tab byte in a header value", fn() {
        request.request(
          current_connection(),
          request.Post,
          "/upload",
          [#("X-Trace", "abc\u{000B}def")],
          <<>>,
          request.options(),
        )
        |> expect.to_equal(
          Error(error.InvalidOptions("Request(InvalidHeaderValue)")),
        )
      }),
      startest.it("rejects a form-feed byte in a header value", fn() {
        request.request(
          current_connection(),
          request.Post,
          "/upload",
          [#("X-Trace", "abc\u{000C}def")],
          <<>>,
          request.options(),
        )
        |> expect.to_equal(
          Error(error.InvalidOptions("Request(InvalidHeaderValue)")),
        )
      }),
      startest.it("accepts a horizontal tab byte in a header value", fn() {
        let assert Ok(_stream) =
          request.start_stream(
            current_connection(),
            request.Post,
            "/upload",
            [#("X-Trace", "abc\tdef")],
            request.options(),
          )
        capture_stream_headers()
        |> expect.to_equal(Ok(#("POST", "/upload", [#("x-trace", "abc\tdef")])))
      }),
      startest.it("rejects a header name that is not an RFC 7230 token", fn() {
        request.request(
          current_connection(),
          request.Post,
          "/upload",
          [#("X-Trace: evil", "abc")],
          <<>>,
          request.options(),
        )
        |> expect.to_equal(
          Error(error.InvalidOptions("Request(InvalidHeaderName)")),
        )
      }),
      startest.it("rejects a CRLF-injected header name", fn() {
        request.request(
          current_connection(),
          request.Post,
          "/upload",
          [#("X-Trace\r\nX-Injected", "evil")],
          <<>>,
          request.options(),
        )
        |> expect.to_equal(
          Error(error.InvalidOptions("Request(InvalidHeaderName)")),
        )
      }),
      startest.it("rejects a caller-supplied Transfer-Encoding header", fn() {
        request.request(
          current_connection(),
          request.Post,
          "/upload",
          [#("Transfer-Encoding", "chunked")],
          <<>>,
          request.options(),
        )
        |> expect.to_equal(
          Error(error.InvalidOptions("Request(ForbiddenTransferEncodingHeader)")),
        )
      }),
      startest.it("rejects duplicate Content-Length headers", fn() {
        request.request(
          current_connection(),
          request.Post,
          "/upload",
          [#("Content-Length", "4"), #("Content-Length", "9999")],
          <<"data":utf8>>,
          request.options(),
        )
        |> expect.to_equal(
          Error(error.InvalidOptions("Request(DuplicateContentLengthHeader)")),
        )
      }),
      startest.it("rejects a non-numeric Content-Length header", fn() {
        request.request(
          current_connection(),
          request.Post,
          "/upload",
          [#("Content-Length", "4 ; charset=evil")],
          <<"data":utf8>>,
          request.options(),
        )
        |> expect.to_equal(
          Error(error.InvalidOptions("Request(InvalidContentLengthHeader)")),
        )
      }),
      startest.it("rejects a CRLF-split custom request method", fn() {
        request.request(
          current_connection(),
          request.Custom("GET /other HTTP/1.1\r\nHost: evil"),
          "/upload",
          [],
          <<>>,
          request.options(),
        )
        |> expect.to_equal(
          Error(error.InvalidOptions("Request(InvalidMethod)")),
        )
      }),
      startest.it("applies the same guards to start_stream", fn() {
        request.start_stream(
          current_connection(),
          request.Post,
          "/upload",
          [#("X-Trace", "abc\r\nX-Injected: evil")],
          request.options(),
        )
        |> expect.to_equal(
          Error(error.InvalidOptions("Request(InvalidHeaderValue)")),
        )
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
