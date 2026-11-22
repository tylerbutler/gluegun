---
title: Installation
description: Add Gluegun to a Gleam project and check runtime compatibility.
next:
  link: /quick-start/
  label: Send your first request
---

Install Gluegun from [Hex](https://hex.pm/packages/gluegun). The examples on
this site also use standard HTTP types such as `http.Get` from `gleam_http`,
so add both packages to `gleam.toml`:

```toml
[dependencies]
gleam_http = ">= 4.0.0 and < 5.0.0"
gluegun = ">= 1.0.0 and < 2.0.0"
```

`gleam add gluegun@1 gleam_http@4` adds both dependencies in one command.

<nav class="gg-lifecycle" aria-label="Request lifecycle">
  <ol>
    <li aria-current="step">Install</li>
    <li>Connect + await</li>
    <li>Request + response</li>
    <li>Close</li>
  </ol>
</nav>

If you edited `gleam.toml` by hand, download the dependencies:

```sh
gleam deps download
```

## Git installation

To use unreleased work, replace the Gluegun dependency with a Git reference:

```toml
gluegun = { git = "https://github.com/tylerbutler/gluegun.git", ref = "v1.0.0" }
```

Run `gleam deps download` again. A tag or commit SHA gives a build that you can
repeat; `ref = "main"` follows the latest revision.

## Compatibility

Gluegun is an interface to the Erlang Gun client, so it runs only on the
Erlang target. It supports Erlang/OTP `>= 27`, Gleam `>= 1.11.0`, and Gun
`>= 2.1.0 and < 3.0.0`.

If your application supports more than one target, keep Gluegun code in
Erlang-only modules. If the package targets only Erlang, set the target in
`gleam.toml`:

```toml
target = "erlang"
```

## Package dependencies

Gluegun depends on `gleam_stdlib`, `gleam_erlang`, `gleam_http`, and `gun`.
Its own `gleam.toml` controls their versions, so you add only `gleam_http`,
and only because your code imports it.

The [API reference](/reference/) and [HexDocs](https://hexdocs.pm/gluegun/)
document each module. Maintainers can find the publication and verification
checks in the
[release setup instructions](https://github.com/tylerbutler/gluegun/blob/main/CONTRIBUTING.md#hex-release-setup).
