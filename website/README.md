# Website deployment

Deploy the static Astro site with Cloudflare Workers Builds. You do not need
an Astro adapter or a Worker entry point.

## Cloudflare setup

Create a Worker named `gluegun-docs` and connect it to the
`tylerbutler/gluegun` GitHub repository. Under **Settings > Build**, use:

| Setting | Value |
| --- | --- |
| Production branch | `main` |
| Root directory | `website` |
| Build command | `pnpm run build` |
| Deploy command | `pnpm run deploy` |
| Preview command | `pnpm run deploy:preview` |

Enable builds for non-production branches to get preview URLs. The preview
command creates or updates a branch Preview without changing the production
deployment. The empty `previews` block in `wrangler.jsonc` enables this command;
static assets and compatibility settings stay at the top level.
Cloudflare installs dependencies with the pnpm version in `package.json`.
Set the `NODE_VERSION` build variable to the Node version in `.mise.toml`.

Deployment builds use committed reference pages and require Node and pnpm only.
`pnpm run build` checks source and page fingerprints before Astro runs. After
source, package manifest, or tool-version changes, run `just site-reference`
from the repository root and commit the generated reference pages and
`website/reference-state.json`. Generation requires Gleam, Erlang, and rebar3.
CI compares the committed pages with fresh Gleam metadata using
`pnpm check:reference`.

Keep the default build watch paths (`*`) so changes to `main` trigger
production builds. Cloudflare applies watch paths to production and preview
builds. Include source and package manifest changes that affect reference pages.

After you verify the site on its `workers.dev` URL, add
`gluegun.tylerbutler.com` under **Settings > Domains & Routes > Custom Domain**.
The domain must use a Cloudflare DNS zone. Remove the existing Netlify DNS
record when you add the custom domain, then verify the site at that domain
before you disable the Netlify project. Keep the Astro `site` URL unchanged.

## Local validation

From the repository root, run:

```sh
just site-check
just site-build
cd website
pnpm run deploy --dry-run
pnpm exec wrangler dev
```

Use the local Wrangler URL to check page routes, redirects, and the 404 page.
The dry run validates the deployment configuration without uploading assets.
For a manual deployment, run `pnpm run deploy` after a build and authenticate
with `pnpm exec wrangler login` or Cloudflare API credentials.

## Streaming guide validation

The [streaming acceptance tests](../test/bounded_streaming_test.gleam) check
the flow-control and cleanup behavior described in the streaming guide.
Local HTTP/1.1 peers send a 1 MiB HTTP chunk and 4096 small chunks. The tests
confirm that delivery stops when initial credit runs out and resumes after
`update_flow`.

A local HTTP/2 peer fills Gun's advertised stream byte window. The tests
check that finite credit prevents stream `WINDOW_UPDATE` and that replenishing
data-message credit resumes delivery. They also check the final chunk's
cumulative byte count and termination cleanup with a real queued server push.
The byte-policy tests reject bodies from both chunked and close-delimited
responses. The application remains responsible for byte limits and archive
processing.
