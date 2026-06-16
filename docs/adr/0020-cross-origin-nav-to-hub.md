# 20. Cross-origin nav from the dashboard to the hub

- **Status:** Accepted
- **Date:** 2026-06-16

## Context

The dashboard at `live.reecewall.dev` is a standalone static site (vanilla
HTML/JS/CSS on S3 + CloudFront). The portfolio hub at `reecewall.dev` is a
separate React/Vite SPA that owns the Work, CV and About pages. The hub already
links *in* to the dashboard via its project card, but the dashboard's own nav
links were relative (`/`, `/cv`, `/about`), so they resolved to
`live.reecewall.dev/cv` and so on, which 404: those routes do not exist on this
origin, they live on the hub. The dashboard also had no favicon, so the browser
tab did not match the hub. The two sites did not read as one.

W8 is the polish pass that makes the project interview-ready, and a visitor who
lands on the dashboard should be able to move to the hub seamlessly.

## Decision

The dashboard nav links **absolutely** to the hub: the wordmark and the Work link
point to `https://reecewall.dev`, with `https://reecewall.dev/cv` and
`https://reecewall.dev/about` for the other two. There is no SPA router here, so
absolute cross-origin links are the correct mechanism rather than client-side
routes. The links are plain same-tab navigation (no `target="_blank"`), since the
intent is one continuous site, not an external reference.

To make the two origins read as one site, the dashboard reuses the hub's exact
brand: the shared `tokens.css` values, the hub's `RW` rounded-pill wordmark
re-implemented in vanilla CSS (the hub is Tailwind; this is a faithful
re-implementation, not a code import), and the hub's exact `favicon.svg` copied
into `web/` and referenced with the same `<link rel="icon" type="image/svg+xml">`
shape.

## Consequences

- **+** Navigation out of the dashboard works and is seamless; the hub owns
  Work/CV/About and the dashboard links to them, closing the loop the hub's
  project card opens.
- **+** Shared tokens, wordmark and favicon make the tab icon and chrome identical
  across both origins, so they present as one brand.
- **-** The hub's routes (`/cv`, `/about`) are now referenced from a second repo.
  If the hub renames a route, this nav must follow. Low risk: the routes are
  stable top-level pages, and the coupling is one-directional and documented here.
- **-** The re-implemented pill can drift from the hub's if the hub restyles its
  nav. Mitigated by using the shared brand tokens rather than hardcoded values,
  so colour and font changes propagate; only structural changes need a manual
  follow-up.
