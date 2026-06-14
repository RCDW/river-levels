# 12. reading_id minted at ingest: assert, don't re-derive

- **Status:** Accepted
- **Date:** 2026-06-14

## Context

Click-to-trace (Feature C) follows one reading across bronze, silver and gold.
That needs a stable key present, unchanged, in every layer. The tempting shortcut
is to recompute a surrogate key in each model from the natural key
(`measure`, `dateTime`); the W1 skeleton did exactly that in silver.

The hub learned a related lesson with its react-pairing gate: a value that must
be consistent everywhere should be **asserted**, not silently re-derived in each
place, because independent re-derivation is where drift hides.

## Decision

Mint **`reading_id = md5(measure|dateTime)` once, at ingest**, in the shared
client (ADR 0010), and carry it unchanged through bronze, silver and gold. Models
**select** it; they never regenerate it. dbt tests assert it is `not_null` and
`unique` in silver and present in gold, so any break in the chain fails CI.

## Consequences

- **+** The trace join is exact by construction: the same row is the same
  `reading_id` in all three layers.
- **+** A single source of truth for the key (the ingest core), guarded by tests.
- **+** If the hash input ever changes, it changes in one place, not three.
- **-** `reading_id` must be minted before bronze is written, so a row with a null
  `measure` or `dateTime` is dropped at ingest rather than carried. Acceptable: a
  row with no stable key cannot be traced anyway.
