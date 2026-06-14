# 5. Per-PR preview environments via subdomain isolation

- **Status:** Accepted
- **Date:** 2026-06-12

## Context

For a presentational site, reviewing rendered reality per PR is more valuable
than reviewing a diff. We want a live, isolated preview for every PR — isolated
from production and from other PRs — without running a long-lived staging
environment.

## Decision

Deploy every PR to **`pr-N.preview.reecewall.dev`** on a stack fully separate
from prod:

- **Separate bucket + CloudFront distribution**, sharing nothing writable with
  production. A wildcard certificate (`*.preview.reecewall.dev`) covers all PRs.
- **One bucket, per-PR key prefixes.** A CloudFront **viewer-request function**
  maps the `pr-N` subdomain to the `/pr-N/*` key prefix, with SPA fallback to
  that PR's `index.html`. The build needs no per-PR config — the edge applies
  the prefix.
- **Least-privilege deploy role.** A separate OIDC role scoped to the preview
  bucket and distribution only; it physically cannot write to or invalidate
  production.
- **Fork-safe.** Fork PRs get no OIDC token, so the deploy job skips cleanly
  rather than failing — own-repo branches only.
- **Lifecycle.** Deploy syncs to `pr-N/` (with scoped `--delete`), invalidates
  and **waits** for completion so downstream checks hit live content, and posts
  a sticky PR comment; a close-triggered job tears the prefix down.

## Consequences

- **+** Every PR is a real, isolated, reviewable environment — and the place
  where the deployed-artifact smoke test and Lighthouse run.
- **+** Blast radius is contained: the preview role can't touch prod, and per-PR
  prefixes isolate PRs from each other.
- **+** No long-lived staging environment to maintain — previews are ephemeral.
- **−** Preview routing, certificate, and teardown are bespoke moving parts.
  Mitigated by the preview workflow self-testing on every PR (it is not
  paths-filtered, so it exercises itself).
