# 10. One ingest module, two runners

- **Status:** Accepted
- **Date:** 2026-06-14

## Context

Ingest runs in GitHub Actions now (W3) and moves to an Azure Function timer at
W6. The risk is two divergent copies of the EA API logic that drift apart.

## Decision

Keep **one** ingest core (`ingest/ea_client.py`) that is deliberately
framework-free (no Actions or Azure imports), with **two thin runners**:
`ingest/run_ingest.py` for Actions now, and `azure_function/` at W6. Both call
the same client; only the entry point and the write target (local Parquet vs
Blob) differ.

Crucially, the trace key is minted in this shared core (ADR 0012), so it is
identical whichever runner produced the data.

## Consequences

- **+** One place for the API contract, the `Reading` shape and reading_id
  minting.
- **+** The W6 migration adds a runner; it does not fork the logic.
- **-** The shared core must stay dependency-light and runner-agnostic; runner
  concerns (Blob clients, Actions env) live in the runners, not the core.
