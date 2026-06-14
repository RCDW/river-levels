# 1. Dependency automation: tuned Dependabot over Renovate

- **Status:** Accepted
- **Date:** 2026-06-14

## Context

Dependency updates are automated with **Dependabot** (`.github/dependabot.yml`):
weekly `pip` (the ingest runtime and the dev/CI toolchain) and `github-actions`
updates, grouped, with an open-PR limit.

The failure mode that matters here is an **uncoordinated major bump of packages
that must move together**. dbt is the obvious one: `dbt-core` and its adapter
`dbt-duckdb` are version-locked in practice. If Dependabot bumps one to a new
major on its own, `dbt build` breaks. This is the data analog of the
react/react-dom blank-page incident the hub hit.

[Renovate](https://docs.renovatebot.com/) is the stronger tool on grouping and
dashboards. This ADR records whether to switch.

## Decision

**Stay on Dependabot, but tune it.** Group `dbt-core` with `dbt-duckdb` so a
major can never land them in separate PRs:

```yaml
groups:
  dbt:
    patterns:
      - "dbt-core"
      - "dbt-duckdb"
```

This prevents the split at the source. Revisit Renovate when we want a
Dependency Dashboard, auto-merge, or a config shared across `reecewall.dev` and
this repo.

## Why not Renovate now

The decisive factor is **trust surface**. We deliberately hardened the supply
chain (every Action pinned to a SHA, minimal `permissions:` on every workflow,
an OSV gate) to shrink third-party access. The hosted Renovate app wants
read/write on the repo, which cuts against that, and we would give up
Dependabot's native security-alert wiring. The concrete pain (coordinated dbt
bumps) is config-fixable here, so the power gap does not yet justify the trade.

## Consequences

- **+** A dbt-core/adapter major can't split and break `dbt build`.
- **+** Zero added trust surface; keeps the SHA-pinned, least-privilege posture.
- **-** We forgo Renovate's dashboard, auto-merge, and richer grouping for now.
- **-** Dependabot's ignore-on-close remains an opaque behaviour to watch.

## Revisit if

We want auto-merge, a Dependency Dashboard, or one dependency policy shared
across `reecewall.dev` and `river-levels`. Then trial self-hosted Renovate.
