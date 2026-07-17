---
title: Installation
description: Add Gluegun to a Gleam project and understand runtime compatibility.
---

Gluegun is distributed as a Git dependency until `1.0`. Add it to your
`gleam.toml`:

```toml
[dependencies]
gluegun = { git = "https://github.com/tylerbutler/gluegun.git", ref = "main" }
```

For reproducible builds, replace `main` with a release tag or commit SHA.

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

The package manages these through `gleam.toml`; applications only need to add the Git dependency above.

See the [API reference](/reference/) for the complete public API.
