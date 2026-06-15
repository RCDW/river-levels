# 13. Click-to-trace v1: pre-computed lineage JSON, DuckDB-WASM later

- **Status:** Accepted
- **Date:** 2026-06-14

## Context

Click-to-trace (Feature C) is the signature feature: click a chart point and see
that reading's journey through bronze, silver and gold. The eventual form (W7)
runs the trace as a live query in the browser with **DuckDB-WASM** over the layer
Parquet, so a reviewer can watch real SQL cross the layers.

W4–W5 ships the interactive features *before* that engine exists. Standing up
DuckDB-WASM now would mean shipping the WASM runtime and fetching layer Parquet
into the browser (a large, separable piece of work) just to render three cards.
We want the feature visible and honest now, without pulling W7 forward.

## Decision

Ship Feature C as **v1: a pre-computed `lineage.json`** the publish step emits,
keyed by `reading_id` (ADR 0012). For every plotted gold point it carries the raw
bronze copies (with their count), the deduped silver row, and the gold value. The
front-end looks up the clicked point's `reading_id` and renders the three layer
cards from that JSON: no query engine, no Parquet in the browser.

The JSON is shaped as **exactly the payload a W7 DuckDB-WASM query will produce**.
The dedup story (bronze may hold more than one ingested copy; silver kept the
latest) is computed from the real layers in `publish/export.py`, not asserted.

## Consequences

- **+** The signature feature is live and honest at W5, showing the real
  per-reading dedup, with no new browser dependency.
- **+** The W7 upgrade is a **source swap, not a redesign**: replace the
  `fetch('lineage.json')` lookup with a DuckDB-WASM query that returns the same
  shape; the cards are untouched. This is what keeps the layers individually
  queryable (ADR 0008) worth the cost.
- **+** Lazy-loaded and scoped to the plotted window, so it never blocks the
  three-second first paint.
- **-** The trace is pre-computed, not live: it answers only for points already
  plotted, and refreshes on the pipeline's schedule rather than on demand. That is
  the honest limit of v1 and the reason W7 exists; until then the cards say what
  they are.
- **-** A second artifact to keep in step with gold. Mitigated by emitting it in
  the same publish step from the same warehouse, so it cannot drift from gold.
