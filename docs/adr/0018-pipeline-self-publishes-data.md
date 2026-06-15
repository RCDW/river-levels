# 18. Pipeline self-publishes fresh data to the edge

- **Status:** Accepted
- **Date:** 2026-06-15

## Context

`deploy.yml` only fires on pushes to `main` that touch `web/**` (plus manual
dispatch). The scheduled pipeline force-pushes fresh artifacts to the `data`
branch, but nothing syncs that branch to S3/CloudFront, so the edge keeps serving
whatever data shipped with the last *code* deploy, not the last *pipeline* run.
The "updated N min ago" badge and the health panel therefore overstate freshness.

The root cause is the hosting model: AWS S3 + CloudFront has no
git-push-to-deploy (unlike the Vercel/Netlify model the original design loosely
assumed), so a branch push does not reach the CDN on its own.

This is a standing bug, but W7 makes it a hard blocker: Feature C runs the
click-to-trace as live DuckDB-WASM SQL over the layer Parquet **served from the
edge**, so stale edge data would make the signature feature query stale data.

## Decision

The data pipeline publishes its own fresh data to the edge. After publishing, it
assumes a dedicated AWS OIDC role and runs a **scoped** `aws s3 sync` of just the
`web/data` directory into the `data/` prefix, then a **scoped** CloudFront
invalidation of `/data/*`. `deploy.yml` is unchanged and still owns code/asset
deploys (a full-site sync and a `/*` invalidation on `web/**` changes).

The pipeline uses its **own** least-privilege role, not the full-site deploy
role: `s3:PutObject`/`s3:DeleteObject` confined to `data/*`, `s3:ListBucket`
scoped to the `data/*` prefix, and `cloudfront:CreateInvalidation` on the one
distribution (ADR follows the deploy role's least-privilege pattern). It still
also pushes to the `data` branch, which stays the durable record and the source
`deploy.yml` pulls `web/data` from on a code deploy.

Alternatives considered and rejected: a `deploy.yml` `workflow_run` trigger after
the pipeline, and a `data`-branch push trigger on `deploy.yml`. Both couple data
freshness to the full-site deploy path and would run a whole-site sync plus a
`/*` invalidation on every routine data refresh, which is broader and less
efficient than the scoped data publish.

## Consequences

- **+** The edge serves genuinely current data on the pipeline's schedule; the
  freshness badge and health panel are now honest.
- **+** Clean separation: "deploy the app" (on code change) versus "publish fresh
  data" (on schedule). The data sync is narrow and cheap, a `/data/*`
  invalidation over the `data/` prefix only.
- **+** Least privilege: the publish identity cannot touch the rest of the site,
  and is auditable on its own.
- **-** The pipeline job now spans two clouds (the Azure lake and the AWS edge)
  and carries a second federated credential. Acceptable: both are OIDC, no stored
  keys, and `id-token: write` was already requested for `azure/login`.
- **-** Two write paths now reach the same artifacts (the S3 sync and the `data`
  branch push). They are produced by the same publish run in the same job, so
  they cannot drift.
- **-** Requires a new repo variable `DATA_PUBLISH_ROLE_ARN` and a human
  `terraform apply` of the new role before the workflow can assume it. The
  rollback W3 pipeline (`pipeline.yml.disabled`) carries the same step so the
  fallback path stays at parity.
