---
title: Installation
description: Add Gluegun to a Gleam project and check runtime compatibility.
next:
  link: /quick-start/
  label: Send your first request
---

For the 1.0 Hex release, install Gluegun with:

```sh
gleam add gluegun
gleam add gleam_http
```

Add `gleam_http` when you import standard HTTP modules, as the examples do.
Maintainers have configured Hex publication but have not yet published 1.0.
Until that release is available, or to use an unreleased revision, add a Git
dependency to `gleam.toml`:

<nav class="gg-lifecycle" aria-label="Request lifecycle">
  <ol>
    <li aria-current="step">Install</li>
    <li>Connect + await</li>
    <li>Request + response</li>
    <li>Close</li>
  </ol>
</nav>

Add these dependencies to your `gleam.toml`:

```toml
[dependencies]
gleam_http = ">= 4.0.0 and < 5.0.0"
gluegun = { git = "https://github.com/tylerbutler/gluegun.git", ref = "main" }
```

For builds that you can repeat, replace `main` with a release tag or a commit SHA.

Download the dependency:

```sh
gleam deps download
```

## Compatibility

- Gluegun runs on the Erlang target only.
- Gluegun is an interface to the Erlang Gun client. It does not support the JavaScript target.
- Gluegun supports Erlang/OTP `>= 27`.
- Gluegun supports Gleam `>= 1.11.0`.
- Gluegun supports Gun `>= 2.1.0 and < 3.0.0`.

If your application supports more than one target, keep Gluegun code in Erlang-only modules. Set the package target when applicable:

```toml
target = "erlang"
```

## Package dependencies

Gluegun uses these packages:

- `gleam_stdlib`
- `gleam_erlang`
- `gleam_http`
- `gun`

The package controls these through its `gleam.toml`. Add
`gleam_http = ">= 4.0.0 and < 5.0.0"` to your application's dependencies when
you import standard HTTP modules, as the request examples do.
After publication, find versioned API documentation at
`https://hexdocs.pm/gluegun/<version>/`. Until then, use the Git dependency above
and the [website API reference](/reference/). See the
[release setup instructions](https://github.com/tylerbutler/gluegun#hex-release-setup)
for the steps that remain before publication.
