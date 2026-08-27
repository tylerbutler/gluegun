//// Foreign handle types for the Erlang Gun boundary.
////
//// `Connection` and `Stream` are external types: they name Erlang values that
//// have no Gleam representation — a Gun connection process identifier and a
//// Gun stream reference. They have no constructors, so a handle can only ever
//// come from Gun itself, and a connection can never be passed where a stream
//// is expected.

/// The Erlang process identifier of a running Gun connection process.
///
/// Produced by `gluegun/connection.open` and accepted by every Gun operation
/// that acts on a connection.
pub type Connection

/// A Gun stream reference identifying one request, server push, or WebSocket
/// stream on a `Connection`.
///
/// Produced by `gluegun/request`, `gluegun/websocket`, and HTTP/2 push
/// messages.
pub type Stream
