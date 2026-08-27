---
title: Installation
description: Add Gluegun to a Gleam project and check runtime compatibility.
---

Until version `1.0`, Gluegun is available as a Git dependency. Add it to
your `gleam.toml`:

```toml
[dependencies]
gluegun = { git = "https://github.com/tylerbutler/gluegun.git", ref = "main" }
```

For builds that you can repeat, replace `main` with a release tag or a commit SHA.

## Compatibility

- Gluegun runs on the Erlang target only.
- Gluegun is an interface to the Erlang Gun client. It does not support the JavaScript target.
- Gluegun supports Erlang/OTP `>= 27`.
- Gluegun supports Gleam `>= 1.7.0`.
- Gluegun supports Gun `>= 2.1.0 and < 3.0.0`.

If your application supports more than one target, keep Gluegun code in Erlang-only modules. Set the package target when applicable:

```toml
target = "erlang"
```

## Package dependencies

Gluegun uses these packages:

- `gleam_stdlib`
- `gleam_erlang`
- `gleam_otp`
- `gun`

The package controls these through its `gleam.toml`. Applications add only the Git dependency above.

See the [API reference](/reference/) for the full public API.
