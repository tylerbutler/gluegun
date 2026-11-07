# Changelog

## 0.2.0 - 2026-11-07

### Added

#### Typed controls for bounded response streaming and connection setup

Add `request.with_initial_flow` for finite response credit, `connection.with_address_family` for IPv4-only or IPv6-only setup, and separate DNS and TLS handshake timeouts. Add `connection.terminate` to force process exit and flush the caller's Gun messages.

`connection.with_retry` and the root facade now accept a validated `RetryCount`, not a `Timeout`. Use `connection.retry_count(0)` to disable retries. The default is Gun's five retries, not the former accidental count of 5000. `connection.retry` now returns `RetryCount`.

Correct the flow-control unit and the close/shutdown documentation. Flow credit counts data messages, not bytes. `close` stops the process through its supervisor; `shutdown` requests graceful shutdown without waiting.
#### Consistent naming across the request/response API

Header helpers follow one convention throughout: `add_headers` appends, `with_headers` replaces. Other names describe what they do: `websocket.send_close_frame`, `gluegun.new_request`, `request.start_stream`, and `client.request_options`.
#### Error and informational response types

`error.UnsupportedFeature(String)` reports preflight capability checks, such as rejecting WebSocket upgrades on HTTP/2. `response.Informational` is a named record (`Informational(status:, headers:)`) for constructing and pattern-matching `1xx` responses.
#### Expanded documentation

Added a stability/semver policy page and expanded the message-flow guide to cover connection lifecycle (`await_up`, close vs. shutdown), fin/half-close semantics, cancellation post-conditions, flow control, the frame model, and process ownership. The README's streaming example handles informational responses. Docstrings cover every variant across the connection, message, request, response, and websocket modules.
#### A focused public API surface

Generated docs cover only public modules (no FFI or test-only helpers). Connection and Stream handles are exported from their public modules. Raw WebSocket dynamic option setters live under `gluegun/websocket/raw`. The root `gluegun` facade covers the minimal common path, including `await_up`.
#### Initial release

Gluegun is a typed Gleam wrapper for the Erlang Gun HTTP client, covering connection options, HTTP request streaming, asynchronous message decoding, high-level HTTP response collection, and WebSocket helpers. Ships with documentation and examples.
#### `tls.insecure()` development opt-out

`tls.insecure()` disables peer verification and SNI for development against self-signed endpoints.
#### Public teardown for reusable WebSocket sockets

Add `websocket.close(socket)` and `gluegun.websocket_close` to wait for a peer close within one finite deadline, terminate the Gun process, and flush the receiver's queued Gun messages. Cleanup still runs after handshake timeout or failure, and repeated close is safe. Reuse teardown in `with_socket` while preserving callback-error precedence. Keep `send_close_frame` as a frame-send operation and update the reusable-socket guidance and echo example.
#### TLS configuration builders for connection options

The typed `gluegun/tls` module and `connection.with_tls_opts` let callers configure peer verification, CA sources, TLS versions, SNI, and client certificate files, rather than relying on Gun's insecure `verify_none` default.

### Changed

#### Better-formatted reference docs

Reference docs render Gleam-formatted code blocks: typed example variables (a/b/c), current-module qualifiers elided, multi-line constructors and function params, sum-type blocks, and deprecation admonitions.
#### Typed Erlang FFI boundary

Every value that crosses the Gun FFI boundary now has a precise type. Connections and streams are opaque foreign handles instead of wrapped Erlang terms, connection, TLS, and WebSocket upgrade options cross as typed option lists, Gun messages are decoded into `message.Message` in Erlang, and every FFI call returns `Result(value, error.GluegunError)` directly. `message.decode` now takes a `message.GunMessage`, and `websocket/raw` sets `reply_to` from a `Pid`, `tunnel` from a `Stream`, and `user_opts` from any Gleam value.
#### Validated timeout construction

`connection.Timeout` is now opaque. Replace `connection.Milliseconds(value)` with `connection.milliseconds(value)`, which returns a `Result`, and replace `connection.Infinity` with `connection.infinity()`.

### Fixed

#### Auto transport no longer silently drops configured TLS options

Previously, `connection.Auto` left Gun's `transport` option unset, so Gun chose TLS only for port 443 and plain TCP for every other port — even when the caller had explicitly configured `tls.TlsOptions` via `with_tls_options`. TLS settings were silently discarded and the connection sent plaintext.

`connection.Auto` now resolves to TLS whenever TLS options were explicitly configured, regardless of port. Auto connections that never configure TLS options are unaffected: Gun still chooses transport purely from the port number.
#### Reject non-byte-aligned payloads before sending to Gun

HTTP request bodies and streamed chunks now return `InvalidOptions` for `BitArray` values with trailing bits. WebSocket binary, ping, pong, and close-reason payloads return `InvalidMessage` for the same values. Rejected sends do not reach Gun or close the connection; a rejected WebSocket batch sends no frames. Empty and byte-aligned payloads are preserved without padding or truncation.
#### Gun mailbox messages and trailered bodies

`message.decode` now accepts the raw mailbox tuples Gun sends to the process that owns a stream (`gun_response`, `gun_data`, `gun_inform`, `gun_trailers`, `gun_push`, `gun_upgrade`, `gun_ws`). `message.await_body` now returns the collected body when the response ends with trailers instead of reporting a stream error.
#### Cancel failed HTTP client streams and drain their queued messages

High-level HTTP helpers now attempt stream-local cleanup after collection errors, including timeouts, invalid messages, and receive failures. They preserve the original error, concurrent streams, and the shared connection. Cleanup failures produce a warning. Cancellation remains asynchronous: the drain removes currently queued messages, but messages in transit can arrive afterward. Use a separate receiving process with the low-level API when strict mailbox isolation is required.
#### `message.decode` preserves stream identity to prevent cross-stream message confusion

`message.decode` discarded the connection pid and stream reference carried in every Gun mailbox tuple, so a decoded `Message` could not be attributed to the stream it came from. A process handling several concurrent streams on one connection (HTTP/2 requests and server pushes sharing a mailbox, or several requests routed to one `reply_to` process) had no reliable way to tell which stream a decoded message belonged to, risking cross-stream confusion.

`message.decode` now returns `Result(message.Envelope, error.GluegunError)`. `Envelope(connection:, stream:, message:)` pairs the decoded `Message` with the connection and stream Gun named for it; for `Push` messages `stream` is the existing stream that received the push notification, not the new stream carried inside `message.Push`.

`decode` now only accepts the raw mailbox tuples Gun sends to the stream owner (`gun_response`, `gun_data`, `gun_inform`, `gun_trailers`, `gun_push`, `gun_upgrade`, `gun_ws`), since only those carry real stream identity; the shorter terms `gun:await/3` returns have none to preserve and are rejected with `DecodeError`. `message.await` and `message.await_body` are unaffected: their caller already supplies the connection and stream explicitly.
#### Reject HTTP request splitting and smuggling inputs at the Erlang FFI boundary

`request`, `headers`, and `ws_upgrade` now validate everything that lands on the request line or in request headers before calling Gun. Request paths and methods must be non-empty and free of control bytes, spaces, and DEL (including CR/LF); header names must be RFC 7230 tokens; header values must be free of control bytes other than HTAB, and DEL; a caller-supplied `Transfer-Encoding` header is rejected; and duplicate or malformed `Content-Length` headers are rejected. Invalid input now returns `InvalidOptions` instead of reaching Gun's request-line and header encoder. Header-name lowercasing on the request path is now ASCII-only instead of Unicode-aware.
#### TLS connections are now **secure by default**

When a connection uses `connection.Tls` (or `connection.Auto` resolving to TLS), Gluegun fills in any unset TLS option fields with `verify_peer`, the OS trust store via `public_key:cacerts_get/0` (OTP 25+), TLS 1.2/1.3, SNI derived from the host passed to `connection.open`, and an HTTPS hostname match function. User-supplied `tls.TlsOptions` fields always win.

This is a behaviour change for any caller that previously relied on Erlang SSL's historical `verify_none` default. To restore the prior permissive behaviour for development, wrap the new helper `tls.insecure()` in `connection.with_tls_opts`. Do not ship `tls.insecure()` to production.

If the host does not provide a system trust store, `connection.open` returns `InvalidOptions("#(\"tls\", \"no_system_cacerts\")")`; supply CAs with `tls.with_cacerts` or `tls.with_cacertfile`.
#### Validate WebSocket control frames before sending

Ping and Pong payloads now have a 125-byte limit. Close reasons must contain valid UTF-8 and at most 123 bytes, with a valid close code. Invalid frames return `InvalidMessage` before Gun receives them, so they cannot crash the connection. Frame lists use complete validation before sending any frame.
