# OpenHornet Docs Deployment

This repository builds and deploys the generated OpenHornet documentation site at:

- https://docs.openhornet.com/software/
- https://docs.openhornet.com/hardware/

The generated Doxygen HTML is not committed. GitHub Actions checks out the source
repositories, builds both documentation sets into `public/`, and deploys that
directory to the `openhornet-docs` Cloudflare Pages project.

## Required Secrets

Set these repository secrets before relying on automatic deployments:

```text
CLOUDFLARE_ACCOUNT_ID
CLOUDFLARE_API_TOKEN
```

`CLOUDFLARE_API_TOKEN` needs permission to edit Cloudflare Pages for the
OpenHornet account.

The source repositories should also define `DOCS_DEPLOY_DISPATCH_TOKEN`, scoped
so their workflows can call `repository_dispatch` on this repository.

## Local Build

The CI script expects both source repositories under `sources/`:

```text
sources/software
sources/hardware
```

Then run:

```bash
scripts/build-docs.sh
```
