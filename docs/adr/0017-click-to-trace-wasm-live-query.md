# 17. Click-to-trace v2: live DuckDB-WASM query, lineage.json as fallback

- **Status:** Accepted
- **Date:** 2026-06-15

## Context

ADR 0013 shipped Feature C as a pre-computed `lineage.json` and committed to the
eventual form, a live DuckDB-WASM query in the browser, "later" (W7). The v1
payload was shaped so that this upgrade would be a **source swap, not a
redesign**. This is that upgrade.

The layer Parquet (a bronze rolling window, silver, and gold_series) is published
to the edge and now reaches it on the pipeline's schedule (ADR 0018), served
same-origin from `/data/parquet/`. So an in-browser engine can query the real
layers by `reading_id` with HTTP range reads, with no CORS to manage.

## Decision

On the **first** point click, lazy-initialise DuckDB-WASM (pinned to
`@duckdb/duckdb-wasm@1.29.0`), register the three layer Parquet files for HTTP
range reads, and run three queries by `reading_id` to populate the **same**
bronze / silver / gold cards. The engine and its WASM runtime load only on that
first trace, so the three-second demo paints untouched.

`reading_id` is sanitised to md5 hex and also bound as a prepared-statement
parameter (belt and braces); timestamps are cast to text in SQL so they match the
v1 format; every value is rendered through the existing `textContent` DOM helpers,
never `innerHTML`. `lineage.json` is **kept as a graceful fallback** for when the
engine cannot load (an unsupported browser, a network failure); a single renderer
draws the cards for both paths, so they are identical regardless of source.

This **supersedes 0013**: the "later" is now realised, and the pre-computed
artifact is demoted from the primary source to the fallback, not removed.

## Consequences

- **+** The trace is now real SQL a reviewer can watch cross the layers, over
  Parquet via range reads (only the needed bytes are fetched). The same gold
  model is queryable three ways: DuckDB-WASM here, DuckDB at build, Synapse
  serverless in Azure.
- **+** Live and on demand: it answers for any plotted reading without a
  pre-computed entry, and the dedup story (bronze may hold more than one copy;
  silver kept the latest) is computed live from bronze at click time.
- **+** Robust: the `lineage.json` fallback means no regression where WASM is
  unavailable, and the W5 work is not wasted.
- **-** A runtime dependency fetched from a CDN (pinned) plus a WASM payload, both
  loaded lazily so first paint is unaffected.
- **-** Two code paths to keep in step (live and fallback). Mitigated by one
  renderer and the identical payload shape.
- **-** The trace is only as fresh as the layer Parquet at the edge (ADR 0018),
  and reaches back only as far as the bronze rolling window (90 days), which
  comfortably covers the 30-day plotted range.
