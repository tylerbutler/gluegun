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
command uploads a version without changing the production deployment.
Cloudflare installs dependencies with the pnpm version in `package.json`.
Set the `NODE_VERSION` build variable to the Node version in `.tool-versions`.

Keep the default build watch paths (`*`) so changes to `main` trigger
production builds. Cloudflare applies watch paths to production and preview
builds; the former Netlify configuration skipped website-unchanged previews
but built production commits.

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
