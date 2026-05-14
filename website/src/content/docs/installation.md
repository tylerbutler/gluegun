---
title: Installation
description: Add Gluegun to a Gleam project and understand runtime compatibility.
---

Install Gluegun with Gleam:

```sh
gleam add gluegun
```

## Compatibility

- Gluegun targets Erlang only.
- Gluegun wraps the Erlang Gun client and does not support the JavaScript target.
- Gluegun supports Gleam `>= 1.7.0`.
- Gluegun supports Gun `>= 2.1.0 and < 3.0.0`.

If your application supports multiple targets, keep Gluegun usage in Erlang-only code and set the package target when appropriate:

```toml
target = "erlang"
```

## Package dependencies

Gluegun depends on:

- `gleam_stdlib`
- `gleam_erlang`
- `gleam_otp`
- `gun`

The package manages these through `gleam.toml`; applications usually only need to run `gleam add gluegun`.

See the [API reference](/reference/) for the complete public API.
