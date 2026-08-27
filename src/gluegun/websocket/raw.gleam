//// Internal raw WebSocket upgrade option helpers.
////
//// These helpers set the Gun `ws_opts` fields that carry Erlang runtime
//// values rather than plain configuration: the process Gun replies to, the
//// tunnel stream to send the upgrade through, and the opaque options Gun
//// forwards to a protocol handler module.

import gleam/erlang/process.{type Pid}
import gluegun/internal.{type Stream}
import gluegun/websocket.{type HandlerOptions, type UpgradeOptions}

/// Set Gun's `reply_to` upgrade option so WebSocket messages are delivered to
/// `reply_to` instead of the calling process.
pub fn with_reply_to(options: UpgradeOptions, reply_to: Pid) -> UpgradeOptions {
  websocket.with_reply_to_raw(options, reply_to)
}

/// Set Gun's `tunnel` upgrade option so the upgrade is sent through an
/// existing tunnel stream.
pub fn with_tunnel(
  options: UpgradeOptions,
  tunnel tunnel: Stream,
) -> UpgradeOptions {
  websocket.with_tunnel_raw(options, tunnel)
}

/// Set Gun's `user_opts` upgrade option, forwarded unchanged to the protocol
/// handler module.
pub fn with_handler_options(
  options: UpgradeOptions,
  handler_options handler_options: HandlerOptions,
) -> UpgradeOptions {
  websocket.with_handler_options_raw(options, handler_options)
}

/// Wrap any Gleam value as the `user_opts` term Gun forwards to the protocol
/// handler module.
@external(erlang, "gluegun_ffi", "identity")
pub fn handler_options(value: value) -> HandlerOptions
