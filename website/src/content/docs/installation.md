---
title: Installation
description: Add Gluegun to a Gleam project and check runtime compatibility.
next:
  link: /quick-start/
  label: Send your first request
---

Gluegun [`1.0.0-rc.1`](https://hex.pm/packages/gluegun/1.0.0-rc.1) is available
on Hex. It is a release candidate for 1.0, not a stable 1.0 release.
To select this candidate from Hex, add these dependencies to `gleam.toml`:

```toml
[dependencies]
gleam_http = ">= 4.0.0 and < 5.0.0"
gluegun = "== 1.0.0-rc.1"
```

Add `gleam_http` when you import standard HTTP modules, as the examples do.
Use the exact TOML requirement for this prerelease; Gleam 1.19.2 rejects
`gleam add gluegun@1.0.0-rc.1`.

<nav class="gg-lifecycle" aria-label="Request lifecycle">
  <ol>
    <li aria-current="step">Install</li>
    <li>Connect + await</li>
    <li>Request + response</li>
    <li>Close</li>
  </ol>
</nav>

Download the dependencies:

```sh
gleam deps download
```

## Git installation

For Git-based development, replace the Gluegun dependency with a release tag
or an unreleased revision:

```toml
gluegun = { git = "https://github.com/tylerbutler/gluegun.git", ref = "v1.0.0-rc.1" }
```

Run `gleam deps download` again. For an unreleased revision, use `ref = "main"`
or a commit SHA. Use a tag or commit SHA for builds that you can repeat.

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
Use the [website API reference](/reference/) or
[versioned HexDocs](https://hexdocs.pm/gluegun/1.0.0-rc.1/) for this candidate. See the
[release setup instructions](https://github.com/tylerbutler/gluegun#hex-release-setup)
for publication and verification checks.
