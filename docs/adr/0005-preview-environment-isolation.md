# 5. Per-PR isolation via a scoped dbt schema

- **Status:** Accepted (deferred; not built in W1-W3)
- **Date:** 2026-06-14

## Context

The hub deploys every PR to an isolated `pr-N.preview.reecewall.dev` site,
because for a presentational site, reviewing rendered reality beats reviewing a
diff. A data pipeline is different: what a reviewer needs to trust is that the
PR's models **build and pass tests**, not that a second copy of a static site
renders. Standing up per-PR S3 sites here would be cost and moving parts for
little value.

## Decision

When per-PR isolation is added, do it as a **scoped dbt schema/target**, not an
S3 site: `dbt build --target pr_<n>` into a per-PR schema, run `dbt test`, and
drop the schema when the PR closes. This is the data analog of the hub's
subdomain isolation: the same "isolated, disposable, per-PR" idea expressed in
the warehouse rather than at the edge.

**Deferred for W1-W3.** The CI gate already builds and tests every PR against a
deterministic fixture on one shared target, which is sufficient while the model
set is small. The per-PR schema is the shape to reach for when models grow or
when previewing real per-PR data becomes worthwhile.

## Consequences

- **+** Records the intended approach, so it is a deliberate step rather than a
  default to the per-PR sites copied from the hub.
- **+** No preview infrastructure (buckets, wildcard cert, edge routing) to build
  or pay for now; the hub's preview stack was dropped from this repo's Terraform.
- **-** Until built, PRs share one CI build target, so two PRs cannot preview
  divergent data simultaneously. Acceptable at this scale.
