# 14. Azure read via the DuckDB azure extension, not httpfs

- **Status:** Accepted
- **Date:** 2026-06-15
- **Supersedes:** 0009

## Context

ADR 0009 settled the transform engine (dbt + DuckDB now, Azure hybrid at W6)
and, written before the Azure work existed, anticipated that DuckDB would read
bronze from Blob storage "via httpfs" over an `az://` URL. Building W6 showed
that mechanism is wrong: `httpfs` is DuckDB's S3/HTTP extension. ADLS Gen2 is
read by DuckDB's separate **`azure`** extension, with `abfss://` paths and a
secret. 0009 is Accepted and therefore immutable, so this ADR corrects the
mechanism rather than rewriting it.

## Decision

Read bronze from ADLS Gen2 with the DuckDB **`azure` extension**:

- The dbt `azure` target lists `extensions: [azure]` and creates an azure
  secret with `provider: credential_chain` (`cli;managed_identity;env`) and
  `account_name` from `LAKE_ACCOUNT_NAME`. dbt-duckdb makes the secret at
  connection time, so no secret appears in SQL.
- The source glob stays the single `BRONZE_GLOB` env var (still no model
  changes); for the azure target it becomes `abfss://lake/bronze/**/*.parquet`.
- Auth is passwordless everywhere: `az login` locally, OIDC in Actions, managed
  identity in the Function - all resolved by the same credential chain.
- `publish/export.py` re-reads bronze for its lineage step on its own DuckDB
  connection, so it gains a guarded branch that loads the `azure` extension and
  the same credential_chain secret when `BRONZE_GLOB` is an Azure URL. The local
  path is unchanged.

The rest of 0009 still holds: dbt + DuckDB, free transform/serve, the Azure
move as a source-location change rather than a rewrite.

## Consequences

- **+** The hybrid actually works: dbt and publish both read ADLS via the
  supported path.
- **+** No secrets in code or SQL; one credential chain across local, CI and
  the Function.
- **-** A known Linux gotcha: the azure extension can hit a curl CA-path error;
  fix by installing `ca-certificates` / setting the transport option.
- Revisit if DuckDB folds Azure support into a different extension.
