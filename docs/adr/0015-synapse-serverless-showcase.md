# 15. Synapse serverless as a showcase query surface

- **Status:** Accepted
- **Date:** 2026-06-15

## Context

W6 wants to show the gold model is queryable in Azure, not just at build and
(later, W7) in the browser - the "same gold model, three engines" narrative. The
constraint is cost: this is a portfolio that must stay in the low pennies, so a
standing warehouse or a dedicated SQL pool is out.

## Decision

Use **Synapse serverless** (the Built-in pool) to expose external views over the
published gold/silver Parquet in the lake (`synapse/external_views.sql`:
`gold.station_latest`, `gold.series`, `gold.silver_readings`). Serverless is
chosen precisely because it has **no idle cost** - billing is $5/TB processed
with a 10 MB per-query floor and free DDL/cached/failed queries, so MB-scale
scans cost ~£0.00005 each. A one-time `sp_set_data_processed_limit` budget cap
guards the only variable. Access is the workspace managed identity with Storage
Blob Data Reader, so ADLS keeps anonymous access disabled.

The published Parquet is the same files the DuckDB build wrote; the hybrid
workflow uploads them to `lake/publish/` so Synapse and the dashboard read one
artifact.

A dedicated SQL pool was rejected (idle cost); re-deriving gold in T-SQL was
rejected (a second copy of the model that could drift from dbt).

## Consequences

- **+** Demonstrable Azure query surface returning the exact dashboard figures,
  for ~pennies/month.
- **+** No model fork: the views read the published artifact, not a re-implementation.
- **-** Adds a dependency: the workflow must land published Parquet in the lake
  for the views to resolve.
- **-** Serverless's 10 MB floor means trivially small queries are not "free";
  irrelevant at this scale and capped anyway.
