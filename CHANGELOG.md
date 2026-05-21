# Changelog

## Unreleased

### Breaking

- TLS connections are now **secure by default**. When a connection uses
  `connection.Tls` (or `connection.Auto` resolving to TLS), Gluegun fills
  in any unset TLS option fields with `verify_peer`, the OS trust store
  via `public_key:cacerts_get/0` (OTP 25+), TLS 1.2/1.3, SNI derived from
  the host passed to `connection.open`, and an HTTPS hostname match
  function. User-supplied `tls.TlsOptions` fields always win.

  This is a behaviour change for any caller that previously relied on
  Erlang SSL's historical `verify_none` default. To restore the prior
  permissive behaviour for development, wrap the new helper
  `tls.insecure()` in `connection.with_tls_opts`. Do not ship
  `tls.insecure()` to production.

  If the host does not provide a system trust store, `connection.open`
  returns `InvalidOptions("#(\"tls\", \"no_system_cacerts\")")`; supply
  CAs with `tls.with_cacerts` or `tls.with_cacertfile`.

### Added

- `tls.insecure()` — opt-out helper that disables peer verification and
  SNI for development against self-signed endpoints.
