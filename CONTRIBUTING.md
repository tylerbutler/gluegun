# Contributing to Gluegun

This guide follows a change from your first build to a published release.
Set up the tools, run the checks that CI runs, then follow the release steps
that publish the package to Hex.

## Set up and build

Install the build tools pinned in `.mise.toml` with `mise install` and activate
mise in your shell. CI installs the same tools with `jdx/mise-action`. For website
tasks, run `corepack enable` to use the pnpm version in `website/package.json`.

```sh
just deps         # Download dependencies
just build        # Build project
just test         # Run tests
just format       # Format src/ and test/
just format-check # Check formatting
just check        # Type check
just docs         # Build documentation
just ci           # Run all CI checks
just ci-library   # Validate the library and documentation examples
just ci-examples  # Validate and package standalone examples
just main         # Run CI checks and build docs
just td           # Validate the Trellis workspace
```

## BEAM candidate measurements

Run `just measure-beam` from the repository root for the local, compiled
measurement harness for [#103](https://github.com/tylerbutler/gluegun/issues/103).
It uses the current locked dependencies and loopback peers, not public
endpoints. See [the measurement report](scripts/beam-measurements.md) for
workloads, raw results, and limits. This tooling does not change production
cancellation, monitors, TLS trust caching, or header normalization.

## Example packages

The root commands below cover all standalone packages under `examples/`:

```sh
just examples-deps
just examples-format-check
just examples-build
```

Just uses `trellis exec --serial` to run these tasks across the workspace.
Trellis 1.5 accepts package names, not path selectors, so each command checks
its package path and skips work outside `examples/`. Tasks stop after a
failure. Serial execution avoids concurrent writes to the shared Hex cache of
the pinned compiler. `examples-test` runs only in packages with a `test/`
directory. `examples-build` also packages escripts when `gleescript` appears
in the package manifest or lockfile. The examples keep the `workspace`
release lifecycle, so release commands do not version, tag, or publish them.

## Website reference builds

Commit the generated API pages under `website/src/content/docs/reference/`
and `website/reference-state.json` with changes to source files, `gleam.toml`,
`manifest.toml`, the reference generator, or `.mise.toml`.

Install the tools listed in `.mise.toml` and enable Corepack for the pnpm
version in `website/package.json`. Reference generation requires Gleam, Erlang,
and rebar3. Linux tool locks use the Ubuntu 24.04 OTP build. The rebar3 pin
uses the official GitHub release, not a local mise plugin.
Use these commands from the repository root:

```sh
just site-deps             # Install website dependencies
just site-reference        # Build current Gleam metadata and regenerate pages
just site-reference-check  # Compare committed pages with current metadata
just site-check            # Check freshness and Astro content
just site-build            # Check freshness and build website/dist
just site-dev              # Check freshness and start the dev server
just site-preview          # Check freshness and serve the last site build
```

`just site-reference` uses `website/scripts/generate-reference.mjs` to render
`build/dev/docs/gluegun/package-interface.json`. Run it after you edit source
documentation or a public API, then commit its output. It also records hashes
of the source inputs and reference pages. Do not edit generated pages or the
state record by hand. Repeat generation after a merge that changes these inputs.
When a dev server is running, regenerate references after source edits.
The fingerprint supports `.mise.toml` and `.tool-versions` and detects adding,
removing, or migrating these files. It hashes the full files, so any tool
configuration change requires regeneration. Keep at least one supported pin
file; missing tool configuration or required source inputs stop the build.

From `website/`, use `pnpm generate:reference` to regenerate or
`pnpm check:reference` to compare committed pages with fresh metadata.
The comparison does not change committed pages. CI runs this comparison and
the reference tests before it checks and builds the website.

Cloudflare Workers Builds uses `website/` as the build root, runs `pnpm build`,
and deploys the static assets in `dist`. See [website deployment](website/README.md)
for the build and preview configuration.
Production and deploy-preview builds need Node and pnpm only. The build checks
the committed source and page hashes before Astro runs and stops if output is
stale or missing. Local `astro`, `build`, `check:astro`, `dev`, `start`, and `preview`
scripts use the same check. Keep Cloudflare's build watch paths at `*` so source,
package manifests, and build configuration trigger production and preview builds.
Run `just site-build`
before `just site-preview` to serve a current build.

## Dependency audits

mise installs the self-contained `licence_audit` v1.0.0-rc.2 release. It does
not add a Gleam dependency, because the audit tool itself depends on Gluegun.
Run `just audit-licences` for a licence report and `just audit-vulns` for an
OSV vulnerability report. These commands use the root `manifest.toml`,
including development dependencies. They do not audit website npm dependencies
or the separate example lockfiles. Licence reports cover Hex packages;
vulnerability reports cover Hex and GitHub dependencies and report skipped
sources. OSV checks require network access.

The policy in `gleam.toml` allows Apache-2.0, MIT, ISC, and BSD-3-Clause.
Run `just audit-check` to enforce it and check vulnerabilities with
`licence_audit check --vulns`. Other licences and high or critical severity
advisories fail the check. Unknown severity does not fail the check by
default. Input, configuration, or network errors also fail the check.
The report tasks do not enforce these rules.

`just ci-library` runs `audit-check`, so an audit failure fails the Library
job and the required Test check. To change the licence policy, run
`licence_audit update` in an interactive terminal and review the changes
to `gleam.toml`.

## Dependency SBOMs

Run `just sbom` to write `build/sbom/gluegun.cdx.json` with the pinned native
`licence_audit` CLI. The command uses `--reproducible` to create a CycloneDX 1.6
document from checksum-verified locked package archives. It needs network
access on cache misses. The same project files, tool version, options, and
`SOURCE_DATE_EPOCH` produce identical bytes; an unset timestamp uses the Unix
epoch.

The SBOM covers the root `manifest.toml`, including development dependencies.
It marks production dependencies as required and development-only dependencies
as optional. It excludes website npm dependencies, standalone example
lockfiles, and the compatibility consumer. Generation does not enforce licence
or vulnerability policy. Keep `just audit-check` for those checks; OSV
enrichment cannot run with `--reproducible`.

Full Library CI checks generate the SBOM and upload the `gluegun-sbom` artifact
with the repository's default retention period. Generation or upload failure
fails Library and the required Test check.

The **Hex release** workflow exports `build/gluegun-<version>.tar` and generates
the SBOM from the same release revision. After package checks, CI, and Hex
publication succeed, it attests provenance for both files and associates the
SBOM with that tarball. It attaches `gluegun-<version>.tar` and
`gluegun.cdx.json` to the existing GitHub release. A retry on the same tag
replaces those assets with files from that tag. Only the release-assets job
has signing and release-write permissions; pull request CI does not sign files.

To verify files from a release, replace the tag and version below with the
release you want to check. These commands apply to releases that include the
SBOM and attestation steps; older tags retain their original workflows.

```sh
gh release download v1.1.0 --repo tylerbutler/gluegun \
  --pattern gluegun-1.1.0.tar --pattern gluegun.cdx.json
gh attestation verify gluegun-1.1.0.tar --repo tylerbutler/gluegun \
  --signer-workflow tylerbutler/gluegun/.github/workflows/publish.yml \
  --source-ref refs/tags/v1.1.0
gh attestation verify gluegun.cdx.json --repo tylerbutler/gluegun \
  --signer-workflow tylerbutler/gluegun/.github/workflows/publish.yml \
  --source-ref refs/tags/v1.1.0
gh attestation verify gluegun-1.1.0.tar --repo tylerbutler/gluegun \
  --signer-workflow tylerbutler/gluegun/.github/workflows/publish.yml \
  --predicate-type https://cyclonedx.org/bom
```

These attestations identify the GitHub asset bytes and their release revision.
They do not prove that Hex received identical bytes: Trellis runs a separate
package build for publication. Verify Hex publication through the release
checks below. Local validation does not establish that GitHub signed or
attached the assets; confirm that after an approved release run.

## CI checks

CI runs library and standalone example checks on separate runners. Each
runner keeps package operations serial. Example tests run before packaging
so Webprobe can reuse its test build. The existing required Test check
requires both the Library and Examples jobs to succeed. Dependency caches
contain downloaded packages and compiled Hex dependencies, but no workspace source, tests,
generated documentation, or escripts. Cache keys include the job, runner image,
active compiler/runtime, rebar3, and root/example dependency manifests.

On pull requests, CI checks workspace metadata but omits code and website
work when changes affect only agent skills/commands or changelog files.
Other changes run the full checks, including README and guide edits.
Failed check selection fails the existing job checks. Main and tag workflows
run the full checks. Compatibility commands use explicit `mise exec`
versions and verify the compiler and exact OTP version before compilation.

Add an unreleased change with:

```sh
just change --kind Added --body "Describe the change"
```

Preview the next release with `just changelog-preview`. Trellis creates release
pull requests from pending fragments on `main`. The `Breaking` fragment kind
still requests a minor release in `gleam.toml`. Before preparing a breaking
1.x release, change its bump to `major` to match the
[API stability policy](https://gluegun.tylerbutler.com/advanced/stability/).
Merge `release/pending` to create
an exact `v{version}` tag and a GitHub release. Tag pushes run CI and package
export, then publish to Hex and HexDocs if checks pass. This includes 0.x
versions and release candidates. Trellis uses the `hex` lifecycle.

## Hex release setup

Maintainers authorize automatic Hex publication by merging the reviewed
release PR. Track publication verification in
[#55](https://github.com/tylerbutler/gluegun/issues/55). Configuration and dry-run
checks do not establish that Hex accepted a package or that HexDocs serves it.

Find published releases on [Hex](https://hex.pm/packages/gluegun) and their
API documentation on [HexDocs](https://hexdocs.pm/gluegun/).

For each release:

1. Select the intended candidate or stable version through the existing
   release process. Do not overwrite or duplicate `release/pending`.
2. Before merging, review the release version and generated documentation.
   Merging the release PR creates the immutable `v{version}` tag and triggers
   publication for all release versions. The **Hex release** workflow checks
   the tag against `gleam.toml` and ancestry on `main`, and exports the package.
   It requires CI, compatibility, examples, documentation, and reference
   freshness checks before publication.
3. Build and inspect with `gleam export hex-tarball`. Check `metadata.config`
   and its nested `contents.tar.gz`: include the licence, Gleam modules, and
   `src/gluegun_ffi.erl`; exclude test/compatibility helpers, build output,
   credentials, and development artifacts. Review production dependencies.
   `trellis publish --dry-run --tag v1.0.0` checks tag selection and dependency
   rewrites from the corresponding checkout; it does not replace the test suite.
4. Confirm the repository's `HEXPM_API_KEY` Actions secret contains a scoped
   Hex key with package and documentation publishing access. Read secret names
   with `gh secret list --repo tylerbutler/gluegun`; do not print secret values.
   The required secret names were present during setup, but this check cannot
   establish key validity, scope, or package ownership. Existing
   `RELEASE_APP_ID` and `RELEASE_APP_PRIVATE_KEY` support GitHub release
   operations, not Hex publication. Report missing credentials or access to
   maintainers; configuration work does not authorize secret/settings changes.
5. After merging, monitor the **Hex release** run triggered by the tag push.
   The workflow checks the tagged source,
   runs `trellis publish --tag "$RELEASE_TAG"` with `HEXPM_API_KEY`, then
   runs `gleam docs publish` for that same version. Trellis calls
   `gleam publish --yes`, which uploads the package and API documentation.
   The explicit docs step also completes documentation after a partial upload
   where Trellis skips an existing Hex version.
   Both commands use the compiler in the tagged `.mise.toml`. New release tags
   use Gleam 1.19.2 to avoid conflicting upload Content-Type headers.
6. Confirm the exact version at `https://hex.pm/packages/gluegun/<version>`
   and test the documented dependency in a consumer. Check its API reference
   at `https://hexdocs.pm/gluegun/<version>/` before adding a HexDocs link.
   A successful workflow alone does not confirm public availability.

If publication fails, retain the approved tag and inspect whether Hex
accepted the version before retrying. Do not retag or overwrite a published
version. After confirming the accepted package matches the approved tag,
maintainers can dispatch another run on the same tag:

```sh
gh workflow run publish.yml --repo tylerbutler/gluegun --ref v1.0.0
```

Do not dispatch it on a branch. Trellis skips
existing Hex versions; the docs step uploads documentation for that version.
Do not use `--replace` as a recovery shortcut.

A retry or dispatch on an existing tag uses that tag's workflow, setup action,
and tool pins. A pin change on `main` does not change the tagged publisher.
For a tag with a broken publisher, obtain approval for a new candidate that
includes the fix, or for a separate recovery from the unchanged tagged source
with a verified corrected compiler. The existing workflow has no compiler
override input.

## Release candidates

Run the **Trellis Release** workflow manually on `main` to change release mode:

| Action | `pre` input | `version` input |
| --- | --- | --- |
| Start a candidate cycle | `rc` | Target stable version, for example `1.1.0` |
| Prepare the next candidate | `rc` | Leave empty |
| Promote the current candidate to stable | `none` | Leave empty |
| Prepare a normal stable release | Leave empty | Leave empty, or set a target version |

A new cycle starts at `rc.0`. Merge each candidate PR before preparing the next
candidate. Trellis archives each candidate's changelog fragments under
`.changes/gluegun/` and removes them from `unreleased/`. Stable promotion
includes the archived entries from the candidate cycle. Candidate GitHub
releases are marked as prereleases.

Release preparation uses Trellis 1.5.0's `--prepare-command` to run
`node website/scripts/generate-reference.mjs` after the version changes.
The release commit includes the generated API pages and
`website/reference-state.json` before the first branch push. Generation failure
stops preparation before the push. The existing reference freshness checks
remain enabled for candidate and stable releases.

Automatic pushes to `main` preserve the mode and target of an open release PR.
If no release PR is open and the current version is a candidate, a push prepares
another candidate only when the unreleased fragments have changed since that
candidate's version commit. Automatic pushes do not promote candidates.

Preview candidates locally without changing files:

```sh
just changelog-preview --set gluegun=1.1.0 --pre rc
just changelog-preview --pre rc
just changelog-preview --pre none
```

The last two commands require a candidate version in the local manifest.
The **Auto-tag release** workflow also supports a manual run on `main` to recover
missing tags or GitHub releases. Release preparation requires the
`RELEASE_APP_ID` and `RELEASE_APP_PRIVATE_KEY` Actions secrets. Those workflows
do not use the Hex key; the separate **Hex release** publish job uses
`HEXPM_API_KEY`.
