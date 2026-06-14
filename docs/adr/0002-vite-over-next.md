# 2. Build tool: Vite (SPA) over Next.js

- **Status:** Accepted
- **Date:** 2026-06-12

## Context

This repo is the **hub** of the portfolio: an app shell plus CV, about, and
project landing pages. The data flagship (a live river-levels dashboard) and
other projects live in separate repos, composed at the hosting layer via
subdomains. So this site is small and essentially static — its content is
data-driven at build time, not fetched at runtime, and it has no SSR or
server-runtime needs.

## Decision

Build with **Vite + React + TypeScript + Tailwind v4** as a client-rendered SPA
(react-router-dom for routing), not Next.js.

- **Avoid framework lock-in.** Vite is a thin, swappable build tool; Next couples
  routing, data-fetching, and rendering to one framework's conventions.
- **The site doesn't need what Next adds.** No SSR/ISR, server actions, or API
  routes — a static hub renders fine as a SPA and ships as plain files.
- **Clean fit with static hosting.** `vite build` emits static assets that go
  straight to S3 + CloudFront (ADR 0003); there is no Node server to run or pay
  for.

This is a settled constraint, not to be relitigated: do not migrate to Next.

## Consequences

- **+** Minimal, transparent, fast build with no framework runtime to learn or
  lock into.
- **+** Output is just static files — trivially hostable and cacheable.
- **−** No built-in SSR/SSG. If a future page genuinely needs server rendering
  or SEO-critical SSR, it would be a separate app — which the
  subdomain-composition model already supports.
