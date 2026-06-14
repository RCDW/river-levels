# 11. Last-known-good publish via the data branch

- **Status:** Accepted
- **Date:** 2026-06-14

## Context

The scheduled pipeline refreshes data every few hours. A bad refresh (failed
transform, bad API data) must never replace good published data on the live
dashboard, and the automated data churn must not pollute the human commit
history on `main`.

## Decision

- **Publish only after `dbt test` passes.** In the pipeline, a failed `dbt test`
  stops the job before the publish step, so the previously published artifacts
  (the last-known-good) stay in place.
- **Machine data lives on a `data` branch, not `main`.** The pipeline force-adds
  the published artifacts to a long-lived `data` branch; `main` stays
  human-authored history. Deploy reads `web/` from `main` and `web/data` from the
  `data` branch.

## Consequences

- **+** A broken run is a no-op for the live site, not an outage.
- **+** `main`'s history stays clean and reviewable; data-refresh noise is
  quarantined on `data`.
- **+** `dbt test` is a genuine gate, not decoration.
- **-** Deploy assembles the site from two refs (`main` + `data`), a small extra
  step. Worth it for the clean separation.
