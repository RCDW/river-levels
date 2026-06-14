# 3. Hosting: S3 + CloudFront over Vercel/Netlify

- **Status:** Accepted
- **Date:** 2026-06-12

## Context

The site is static (ADR 0002) and needs hosting, a CDN, TLS, and a deploy
pipeline. Managed platforms (Vercel, Netlify) provide all of this turnkey;
rolling it on AWS is more setup.

## Decision

Host on **AWS S3 + CloudFront**, provisioned with Terraform (ADR 0004) and
deployed from GitHub Actions via OIDC (no stored keys).

Reasons:

- **Build job-relevant AWS / IaC skills.** This is a data-engineer job-search
  portfolio; standing up real AWS infrastructure as code is itself part of the
  product.
- **Own the infrastructure, avoid platform lock-in.** No managed-platform
  abstractions; the S3/CloudFront stack is ours to shape and to move.
- **Cost.** A static site on S3 + CloudFront sits comfortably in low/free-tier
  territory with predictable pricing.
- **Full edge and caching control.** Direct control of CloudFront cache
  behaviour and edge functions — demonstrated by the per-PR preview router
  (ADR 0005), which a managed platform would not expose at this level.

## Consequences

- **+** Transferable cloud skills, full control, low cost, no vendor lock-in.
- **+** Everything — DNS, CDN, certificates, deploy roles — is in Terraform and
  reviewable.
- **−** More to build and maintain than a turnkey platform: the caching
  strategy, cache invalidations, OIDC roles, and preview routing are all
  hand-rolled. (That hand-rolling is itself portfolio signal.)
