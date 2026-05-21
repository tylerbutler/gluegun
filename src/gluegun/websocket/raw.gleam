//// Internal raw WebSocket upgrade option helpers.
////
//// These helpers expose Gun-specific dynamic ws_opts fields for package-internal
//// tests and FFI plumbing.

import gleam/dynamic
import gluegun/websocket

pub fn with_reply_to_dynamic(
  options: websocket.UpgradeOptions,
  reply_to: dynamic.Dynamic,
) -> websocket.UpgradeOptions {
  websocket.with_reply_to_raw(options, reply_to)
}

pub fn with_tunnel_dynamic(
  options: websocket.UpgradeOptions,
  tunnel: dynamic.Dynamic,
) -> websocket.UpgradeOptions {
  websocket.with_tunnel_raw(options, tunnel)
}

pub fn with_user_opts_dynamic(
  options: websocket.UpgradeOptions,
  user_opts: dynamic.Dynamic,
) -> websocket.UpgradeOptions {
  websocket.with_user_opts_raw(options, user_opts)
}
