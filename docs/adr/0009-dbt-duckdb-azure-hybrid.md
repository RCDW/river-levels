# 9. Transform engine: dbt + DuckDB now, Azure hybrid at W6

- **Status:** Accepted
- **Date:** 2026-06-14

## Context

The transform layer needs an engine. Options ranged from hand-written Python
(pandas) to a managed warehouse (Snowflake/BigQuery) to an embedded engine. The
pipeline must run for free on a GitHub Actions schedule now and, later (W6), move
ingest to an Azure Function reading from Blob storage, without rewriting the
transforms.

## Decision

Use **dbt + DuckDB** (`dbt-duckdb`). dbt gives tested, documented, DAG-ordered
SQL models; DuckDB runs them in-process with zero standing infrastructure and
reads Parquet directly. The bronze source is a `read_parquet(...)` over a glob
behind a `BRONZE_GLOB` env var, so the same models run against local Parquet now
and an `az://` Blob URL at W6 (via httpfs) with no model changes.

A managed warehouse was rejected as cost and operational weight unjustified for
this volume; raw pandas was rejected because it gives up the tests, lineage and
DAG that make the pipeline trustworthy and traceable.

## Consequences

- **+** Free to run; no standing infrastructure; fast local iteration.
- **+** Tests, docs and lineage out of the box (the data smoke test in CI).
- **+** The Azure move is a source-location change, not a rewrite.
- **-** DuckDB is single-node; not a fit if data outgrows one machine. Far off at
  this scale.
