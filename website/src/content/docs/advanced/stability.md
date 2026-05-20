---
title: Stability
description: Understand Gluegun's semantic versioning policy and compatibility guarantees.
---

Gluegun 1.0 follows semantic versioning.

## Stable public API

The following modules are stable public API and follow semver compatibility guarantees:

- `gluegun`
- `gluegun/connection`
- `gluegun/request`
- `gluegun/client`
- `gluegun/websocket`
- `gluegun/message`
- `gluegun/response`
- `gluegun/error`
- `gluegun/fin`

Within those modules:

- Adding new functions or options is a minor release.
- Bug fixes and documentation-only changes are patch releases.
- Removing or changing existing public APIs is a major release.

## What is not stable

Items marked `@internal` are not part of the stable API surface, even if generated reference docs mention them for deterministic tests or FFI plumbing. They may change or disappear in any release.

Opaque public types are stable at their documented boundary, but not in their hidden representation.

## Closed ADTs

Gluegun treats these ADTs as closed for compatibility purposes:

- `gluegun/connection.Protocol`
- `gluegun/connection.Transport`
- `gluegun/message.Message`

Adding a new variant to one of those types is a breaking change and requires a major release, because existing caller pattern matches may need to change.

## Runtime compatibility floors

Gluegun currently supports:

- Erlang/OTP `>= 27`
- Gleam `>= 1.7.0`
- Gun `>= 2.1.0 and < 3.0.0`

The OTP floor matches the pinned toolchain and CI baseline. The Gun range comes from `gleam.toml` and is the compatibility range the package is released against.
