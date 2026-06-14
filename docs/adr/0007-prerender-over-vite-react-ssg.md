# 7. Per-route prerender: headless Chromium snapshot over vite-react-ssg

- **Status:** Accepted
- **Date:** 2026-06-14

## Context

The site is a client-rendered SPA (ADR 0002) served from S3 + CloudFront
(ADR 0003) via an OAC REST origin, which does no directory-index resolution.
CloudFront maps `403/404 → /index.html`, so every route (`/cv`, `/about`)
serves the **root** `index.html` and renders client-side. That shell carries no
per-route title, description, or content, so crawlers and link unfurlers see the
same generic markup for every page — poor for SEO on the CV and About pages.

The intended fix was `vite-react-ssg`: prerender each route to static HTML at
build time while keeping the SPA. It turned out to be incompatible with this
stack (see below), forcing a choice between dropping it and adopting a different
prerender mechanism.

## Decision

Prerender public routes with a **custom headless-Chromium snapshot** after the
normal `vite build`, not with an SSG framework.

`vite-react-ssg` is unusable here: its current release hard-imports
`react-router-dom/server.js`, a subpath **react-router 7 removed** (the
static-render APIs moved into the `react-router` core package), so the build
throws `ERR_PACKAGE_PATH_NOT_EXPORTED`. The app is on react-router 7, and there
is no released version of the tool that supports it. (React 19 was fine; RR7 was
the blocker.)

Instead, `scripts/prerender.ts` serves the built `dist/` with `vite preview`,
loads `/`, `/cv`, `/about` in Chromium (the same Playwright tooling the CV PDF
generator already uses), and writes each rendered page back as a nested
`dist/<route>/index.html`. A per-route `usePageMeta` hook
(`apps/web/src/usePageMeta.ts`) sets the title/description so each snapshot is
self-describing. A CloudFront viewer-request function (`infra/router.js`, wired
in `infra/cloudfront.tf`) maps clean URLs to those nested files; `deploy.yml`
uploads all HTML `no-cache` while hashed assets stay immutable.

Reasons this won over alternatives:

- **No new runtime framework or dependency** — reuses Playwright, already
  present for the PDF generator. Nothing new to learn or lock into.
- **Full control and transparency** — a small script we own, not a framework's
  prerender conventions; the same client bundle still boots over the
  prerendered DOM (verified: no console errors).
- **Stays a SPA** — this is a build-time snapshot, not SSR, so it does not
  contradict ADR 0002.

## Consequences

- **+** Each route ships crawlable, self-describing static HTML; the SPA is
  unchanged for users.
- **+** Zero added runtime dependencies.
- **−** The prerender route list is maintained by hand in `scripts/prerender.ts`;
  a new public route must be added there.
- **−** Ordering constraint: the CloudFront router function **must be applied
  before** a prerender build deploys. Otherwise `/cv` 403s → root `index.html`,
  which is now the prerendered Home, producing a wrong-page/hydration mismatch.
- **−** Adds a build step (serve + browser render) to the deploy pipeline.
- Revisit if `vite-react-ssg` (or an equivalent) ships react-router 7 support and
  the route list grows enough that hand-maintaining it becomes a burden.
