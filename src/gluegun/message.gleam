//// Decoding and awaiting asynchronous Gun stream messages.
////
//// Gun sends HTTP, HTTP/2 push, upgrade, and WebSocket events as Erlang
//// messages. This module decodes those messages into Gleam types for callers
//// using lower-level streaming or advanced flows.

import gluegun/connection.{type Connection, type Timeout}
import gluegun/error
import gluegun/fin.{type Fin}
import gluegun/request.{type Stream}

/// Alias for `gluegun/request.Method` used in decoded messages.
pub type Method =
  request.Method

/// Alias for `gluegun/request.Header` used in decoded messages.
pub type Header =
  request.Header

/// WebSocket frames delivered inside Gun stream messages.
///
/// On the wire Gun delivers `close` (atom) as `Close` and
/// `{close, Code, Reason}` as `CloseWithReason`.
pub type Frame {
  /// A UTF-8 text frame. Gun validates the payload as UTF-8 before delivery.
  Text(String)
  /// A binary frame. The payload is an opaque byte string.
  Binary(BitArray)
  /// A ping control frame. Reply with `Pong` to keep the connection alive.
  Ping(BitArray)
  /// A pong control frame. Usually delivered in response to a `Ping`.
  Pong(BitArray)
  /// A close control frame with no status code or reason.
  Close
  /// A close control frame carrying a numeric close code and opaque reason
  /// payload (RFC 6455 §5.5.1).
  CloseWithReason(code: Int, reason: BitArray)
}

/// Gun HTTP stream messages delivered by the Erlang Gun client.
///
/// Sequencing for a normal HTTP response:
/// zero or more `Inform` (1xx) → one `Response` → zero or more `Data` (until
/// `Fin`) → optional `Trailers`. `Push` and `Upgrade` may appear for HTTP/2
/// server push and protocol switching. `WebSocket` only appears after a
/// successful upgrade.
///
/// This type is closed; new variants are a breaking change. Pin to a major
/// version.
pub type Message {
  /// A 1xx informational response. May appear multiple times before the
  /// final `Response`.
  Inform(status: Int, headers: List(Header))
  /// The final HTTP response headers. `fin` is `Fin` when there is no body.
  Response(fin: Fin, status: Int, headers: List(Header))
  /// A response body chunk. `fin` is `Fin` on the last chunk.
  Data(fin: Fin, data: BitArray)
  /// Trailing headers delivered after the body (HTTP/1.1 trailers or HTTP/2
  /// trailer frames).
  Trailers(headers: List(Header))
  /// An HTTP/2 server push. The `stream` is a new stream the caller may
  /// await or cancel.
  Push(stream: Stream, method: Method, uri: String, headers: List(Header))
  /// A successful protocol upgrade. Subsequent messages on this stream use
  /// the new protocol (e.g. WebSocket).
  Upgrade(protocols: List(String), headers: List(Header))
  /// A decoded WebSocket frame. Only delivered after an upgrade.
  WebSocket(frame: Frame)
}

/// Alias for `gluegun/error.GluegunError`.
pub type GluegunError =
  error.GluegunError

/// A raw Gun stream message, exactly as Gun delivers it to the process that
/// owns the stream.
///
/// This external type has no Gleam constructors: values come from Gun itself
/// (or from an Erlang FFI function of your own that receives them). Use
/// `decode` to turn one into a typed `Message`.
pub type GunMessage

/// A decoded `Message` paired with the connection and stream Gun says it
/// belongs to.
///
/// Gun's mailbox tuples (`gun_response`, `gun_data`, `gun_inform`,
/// `gun_trailers`, `gun_push`, `gun_upgrade`, `gun_ws`) always name the
/// connection process and stream reference a message came from. `decode`
/// preserves both alongside the decoded `Message` so a process that owns
/// several concurrent streams — for example an HTTP/2 connection with
/// server push, or several requests sharing one `reply_to` process — can
/// attribute each message to the right stream instead of assuming messages
/// arrive for whichever stream the caller currently has in mind.
///
/// `stream` names the stream that *delivered* the message; for `Push` it is
/// the existing stream the server pushed on, not the new stream carried
/// inside `message.Push`.
pub type Envelope {
  Envelope(connection: Connection, stream: Stream, message: Message)
}

/// Decode a raw Erlang Gun mailbox message into a typed `Message`, paired
/// with the connection and stream it belongs to.
///
/// Useful when receiving Gun messages outside Gluegun's helpers (for example
/// inside a custom `receive` loop that hands the message to Gluegun through
/// your own Erlang FFI). Accepts the mailbox tuples Gun sends to the stream
/// owner (`gun_response`, `gun_data`, `gun_inform`, `gun_trailers`,
/// `gun_push`, `gun_upgrade`, `gun_ws`). Returns `DecodeError` when the term
/// is not a recognized Gun mailbox message shape, including for error
/// messages such as `gun_error` — handle those directly in your `receive`
/// clause instead of passing them to `decode`.
@external(erlang, "gluegun_ffi", "decode_message")
pub fn decode(message: GunMessage) -> Result(Envelope, GluegunError)

/// Await the next Gun message for a stream.
///
/// Blocks the calling process until a message arrives, the stream errors,
/// or `timeout` elapses. Messages arrive in the order described on
/// `Message`: `Inform`* → `Response` → `Data`* → `Trailers`?. Use this for
/// streaming responses, server push, or any flow where you need messages as
/// they arrive.
///
/// Errors: `Timeout`, `ConnectionDown`, `StreamError`, `DecodeError`.
@external(erlang, "gluegun_ffi", "await")
pub fn await(
  connection: Connection,
  stream: Stream,
  timeout: Timeout,
) -> Result(Message, GluegunError)

/// Await and collect the full response body for a stream.
///
/// Drains body chunks until the final `Fin` and returns the concatenated
/// payload. Headers must already have been consumed (e.g. via a prior
/// `await` that returned `Response`). When the response ends with trailers,
/// the collected body is returned and the trailer headers are dropped; use
/// `await` if you need them. For incremental access use `await`
/// directly. The full body is held in memory; use the lower-level loop for
/// very large responses.
///
/// Errors: `Timeout`, `ConnectionDown`, `StreamError`.
@external(erlang, "gluegun_ffi", "await_body")
pub fn await_body(
  connection: Connection,
  stream: Stream,
  timeout: Timeout,
) -> Result(BitArray, GluegunError)
