---
title: Stability
description: Learn the semantic versioning policy and compatibility guarantees of Gluegun.
---

Gluegun 1.0 uses semantic versioning.

## Stable public API

These modules are stable public API. They follow the semver compatibility guarantees:

- `gluegun`
- `gluegun/connection`
- `gluegun/request`
- `gluegun/client`
- `gluegun/websocket`
- `gluegun/message`
- `gluegun/response`
- `gluegun/error`
- `gluegun/fin`

In those modules:

- New functions or options are a minor release.
- Bug fixes and documentation-only changes are patch releases.
- Removal or change of an existing public API is a major release.

## What is not stable

Items marked `@internal` are not part of the stable API. This applies even when the generated reference docs show them for deterministic tests or FFI plumbing. They can change or disappear in any release.

Opaque public types are stable at their documented boundary. Their hidden representation is not stable.

## Closed ADTs

For compatibility, Gluegun treats these ADTs as closed:

- `gluegun/connection.Protocol`
- `gluegun/connection.Transport`
- `gluegun/message.Message`

A new variant in one of those types is a breaking change and requires a major release. Existing pattern matches in caller code can then require changes.

## Minimum runtime versions

Gluegun currently supports:

- Erlang/OTP `>= 27`
- Gleam `>= 1.7.0`
- Gun `>= 2.1.0 and < 3.0.0`

The OTP minimum agrees with the pinned toolchain and the CI baseline. The Gun range comes from `gleam.toml`. It is the compatibility range that the package is released against.
