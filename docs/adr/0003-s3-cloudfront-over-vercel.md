# 3. Hosting: S3 + CloudFront over Vercel/Netlify

- **Status:** Accepted
- **Date:** 2026-06-14

## Context

The dashboard is a static site (HTML/JS reading published JSON and Parquet) and
needs hosting, a CDN, TLS, and a deploy pipeline, served at live.reecewall.dev.
Managed platforms (Vercel, Netlify) provide all of this turnkey; rolling it on
AWS is more setup.

## Decision

Host on **AWS S3 + CloudFront**, provisioned with Terraform (ADR 0004) and
deployed from GitHub Actions via OIDC (no stored keys). This mirrors the
reecewall.dev hub, so the two sites share one hosting pattern.

Reasons:

- **Job-relevant AWS / IaC skills.** This is a data-engineering portfolio;
  standing up real cloud infrastructure as code is part of the product.
- **Own the infrastructure, no platform lock-in.** The S3/CloudFront stack is
  ours to shape and to move.
- **Cost.** A static site on S3 + CloudFront sits in low/free-tier territory.
- **Edge and caching control.** Direct control of CloudFront, which matters more
  as the dashboard grows (range requests for the in-browser DuckDB-WASM trace).

## Consequences

- **+** Transferable cloud skills, full control, low cost, no vendor lock-in.
- **+** DNS, CDN, certificates and deploy roles are all in Terraform and
  reviewable; identical shape to the hub.
- **-** More to build and maintain than a turnkey platform (caching,
  invalidations, OIDC roles are hand-rolled). That hand-rolling is itself signal.
