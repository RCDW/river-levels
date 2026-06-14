# 1. Dependency automation: tuned Dependabot over Renovate

- **Status:** Accepted
- **Date:** 2026-06-12

## Context

Dependency updates are automated with **Dependabot** (`.github/dependabot.yml`):
weekly `npm` and `github-actions` updates, with minor/patch bundled into a
single grouped PR and an open-PR limit of 5.

Several rough edges have been felt:

- **Uncoordinated bumps.** The grouped PR only bundles _minor/patch_, so a
  **major** bump arrives as its own PR. This caused a real production incident:
  Dependabot opened `a1c2088 "bump react-dom and @types/react-dom"` (react-dom
  **18 → 19**) on its own, while `react` stayed at 18. The split built and
  served 200s but never mounted — a blank page in production. We now have a CI
  gate that _catches_ this class (see the react-pairing check), but nothing
  _prevented_ it at the source.
- **ignore-on-close.** Closing a Dependabot PR silently skips that version, with
  no central place to see what has been implicitly skipped.
- **The 5-PR cap** can hide pending updates behind the limit.
- **Grouping is limited** — no cross-manager or conditional rules.
- **The "recreate dance"** — nudging rebases/recreates via `@dependabot`
  comments is manual.

[Renovate](https://docs.renovatebot.com/) is the obvious alternative and is
genuinely stronger on most of these. This ADR records whether to switch.

## Decision

**Stay on Dependabot, but tune it.** Specifically, add a **react-family group
that includes majors**, so `react`, `react-dom`, `@types/react`, and
`@types/react-dom` always bump together in lockstep:

```yaml
groups:
  react: # bump the react runtime + its types together, majors included,
    patterns: # so a react-dom major can never ship without react (prod incident)
      - "react"
      - "react-dom"
      - "@types/react"
      - "@types/react-dom"
  minor-and-patch:
    update-types: ["minor", "patch"]
```

The `react` group is listed first, so the react family is claimed by it (for all
update types, majors included) before the catch-all minor/patch group. This
_prevents_ the incident class at the source — defence-in-depth alongside the CI
gate that _catches_ it.

Revisit **Renovate** when we want a Dependency Dashboard, auto-merge, or a
shared config reused across repos (e.g. the upcoming `river-levels`). At that
point prefer **self-hosted Renovate** (a scheduled GitHub Action) over the
hosted Mend app — see below.

## Why not Renovate now

| Pain point        | Dependabot (tuned)                                                  | Renovate                                                                          |
| ----------------- | ------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Coordinated bumps | **Fixed** here via a react-family group w/ majors                   | Built-in family/monorepo grouping; slightly more ergonomic                        |
| ignore-on-close   | Inherent; no central view                                           | Same behaviour, but the **Dependency Dashboard** makes it transparent — clear win |
| 5-PR cap          | One-line raise; grouping also lowers PR volume                      | `prConcurrentLimit` + `prHourlyLimit`, more granular                              |
| Grouping power    | `patterns` + `update-types` — adequate                              | `packageRules` — arbitrary, per-group schedules/automerge — clear win             |
| Recreate/rebase   | Manual `@dependabot` comments                                       | Auto-rebase + dashboard checkboxes — win                                          |
| **Trust surface** | First-party GitHub; native security-alert wiring; **nothing added** | Hosted = the **Mend GitHub App** with read/write to the repo                      |

The decisive factor for _this_ repo is the last row. We just hardened the
supply chain (pinned every Action to a SHA, minimal `permissions:` everywhere)
specifically to shrink third-party trust surface. Adding a broad-access GitHub
App cuts directly against that, and Dependabot's native security-alert
integration is a real benefit we'd give up. The concrete pains that bit us are
config-fixable in Dependabot, so the power gap doesn't yet justify the trade.

## Consequences

- **+** The production incident class is now prevented at the source, not only
  caught by CI.
- **+** Zero added trust surface; keeps the Task-3 supply-chain posture intact.
- **+** Decision and its trigger conditions are recorded, so a future switch to
  Renovate is a deliberate step, not a default.
- **−** We forgo Renovate's Dependency Dashboard, auto-merge, and richer
  grouping for now.
- **−** ignore-on-close remains an opaque Dependabot behaviour to stay aware of.

## Revisit if

We want auto-merge of low-risk updates, a Dependency Dashboard, or a single
dependency policy shared across `reecewall.dev` and `river-levels`. Then trial
**self-hosted Renovate** and compare in practice.
