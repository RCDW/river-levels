# Architecture Decision Records

Short records of significant, hard-to-reverse decisions and _why_ they were made
— so the reasoning survives the moment and the people. Lightweight,
[MADR](https://adr.github.io/)-style.

## Conventions

- One decision per file, named `NNNN-kebab-title.md`, numbered in order.
- Status is one of `Proposed`, `Accepted`, `Superseded by NNNN`, `Deprecated`.
- ADRs are immutable once `Accepted`: to change a decision, add a new ADR that
  supersedes it and update the old one's status — don't rewrite history.
- Keep them short and high-signal. Record the reasons that **actually** drove
  the decision, not the impressive-sounding ones. Start from `template.md`.

## Index

- [0001 — Dependency automation: tuned Dependabot over Renovate](0001-dependency-automation.md)
- [0002 — Build tool: Vite (SPA) over Next.js](0002-vite-over-next.md)
- [0003 — Hosting: S3 + CloudFront over Vercel/Netlify](0003-s3-cloudfront-over-vercel.md)
- [0004 — IaC: Terraform over AWS CDK / CloudFormation](0004-terraform-over-cdk.md)
- [0005 — Per-PR preview environments via subdomain isolation](0005-preview-environment-isolation.md)
- [0006 — Guarding the react/react-dom major-mismatch class](0006-peer-dependency-gate.md)
- [0007 — Per-route prerender: headless Chromium over vite-react-ssg](0007-prerender-over-vite-react-ssg.md)
