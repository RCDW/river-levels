# 8. Medallion layering: append-only bronze, materialised silver

- **Status:** Accepted
- **Date:** 2026-06-14

## Context

The pipeline could collapse into a single transform (API straight to a
presentation table). The signature feature, click-to-trace, needs the opposite:
a reader must be able to follow one reading from raw API capture, through
cleaning, to the plotted point.

## Decision

Use a **Medallion** layout and keep each layer independently queryable:

- **Bronze is append-only Parquet.** Every ingest run writes a new
  `dt=.../batch_<ts>.parquet`; nothing is overwritten or deleted. Raw capture is
  preserved exactly as received.
- **Silver is materialised as a `table`** (not a view or ephemeral CTE), so it
  exists as a queryable artifact: deduped on the trace key and quality-flagged.
- **Gold** is the small, presentation-shaped output (latest, 24h change, series).

Bronze stays an external Parquet source that downstream models read but never
collapse, so the raw layer remains queryable on its own.

## Consequences

- **+** Each layer is independently queryable, which is what makes click-to-trace
  (Feature C) possible: the same row exists in bronze, silver and gold.
- **+** Append-only bronze is a clean audit log and supports reprocessing.
- **+** Materialised silver is fast to query and stable for the trace.
- **-** Storage grows monotonically (many small bronze files). Acceptable at this
  volume; compaction is a future concern, not a W1-W3 one.

See ADR 0009 for the engine and ADR 0012 for the key that ties the layers
together.
