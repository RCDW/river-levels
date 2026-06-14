# Architecture Decision Records

Short records of significant, hard-to-reverse decisions and _why_ they were
made, so the reasoning survives the moment and the people. Lightweight,
[MADR](https://adr.github.io/)-style.

This log began from the reecewall.dev hub's records: the portable ones were kept
and re-authored for the data context (0001, 0003, 0004, 0005), the web-only ones
were dropped (the old 0002, 0006 and 0007 on Vite, the react peer gate and
prerendering), and the data-specific decisions were added (0008 onward). The gaps
in the numbering are those removed records.

## Conventions

- One decision per file, named `NNNN-kebab-title.md`, numbered in order.
- Status is one of `Proposed`, `Accepted`, `Superseded by NNNN`, `Deprecated`.
- ADRs are immutable once `Accepted`: to change a decision, add a new ADR that
  supersedes it and update the old one's status, rather than rewriting history.
- Keep them short and high-signal. Record the reasons that **actually** drove
  the decision, not the impressive-sounding ones. Start from `template.md`.

## Index

- [0001 - Dependency automation: tuned Dependabot over Renovate](0001-dependency-automation.md)
- [0003 - Hosting: S3 + CloudFront over Vercel/Netlify](0003-s3-cloudfront-over-vercel.md)
- [0004 - IaC: Terraform over AWS CDK / CloudFormation](0004-terraform-over-cdk.md)
- [0005 - Per-PR isolation via a scoped dbt schema](0005-preview-environment-isolation.md)
- [0008 - Medallion layering: append-only bronze, materialised silver](0008-medallion-layering.md)
- [0009 - Transform engine: dbt + DuckDB now, Azure hybrid at W6](0009-dbt-duckdb-azure-hybrid.md)
- [0010 - One ingest module, two runners](0010-one-ingest-two-runners.md)
- [0011 - Last-known-good publish via the data branch](0011-last-known-good-publish.md)
- [0012 - reading_id minted at ingest: assert, don't re-derive](0012-reading-id-at-ingest.md)
