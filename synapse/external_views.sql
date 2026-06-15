/* ============================================================================
   W6 - Synapse serverless SQL: the "same gold, in Synapse" showcase surface.

   This realises the narrative that one gold model is queryable three ways:
   DuckDB at build, DuckDB-WASM in the browser (W7), and Synapse serverless
   here. The views below read the SAME published parquet the DuckDB build
   wrote (uploaded to the lake by the pipeline_azure workflow).

   Cost: serverless has NO idle cost - $5/TB processed, 10 MB minimum per
   query, DDL / failed / cached queries free. Our parquet scans are MB-scale,
   so each query hits the 10 MB floor (~$0.00005). Honest monthly total for
   W6 overall is ~GBP 0.20-0.50 (see docs/w6-cutover-runbook.md).

   BEFORE RUNNING: replace REPLACE_ACCOUNT (3 occurrences) with the lake
   storage account name. Run in the Built-in serverless pool of a Synapse
   workspace whose managed identity has 'Storage Blob Data Reader' on the lake.
   ========================================================================== */

-- 1) One-time cost guardrail. Run in the MASTER database (not river_lake);
--    caps total data processed so a runaway query cannot surprise the bill.
--    All three tiers must satisfy daily <= weekly <= monthly, and 1 TB is the
--    per-tier minimum - so set all three to the floor (a ~$5 monthly ceiling).
--    Setting monthly alone fails: the unset daily/weekly tiers are unlimited,
--    which violates daily <= weekly <= monthly.
EXEC sp_set_data_processed_limit @type = N'daily',   @limit_tb = 1;
EXEC sp_set_data_processed_limit @type = N'weekly',  @limit_tb = 1;
EXEC sp_set_data_processed_limit @type = N'monthly', @limit_tb = 1;
GO

-- 2) Access to the lake: grant the Synapse workspace managed identity
--    'Storage Blob Data Reader' on the storage account, then query directly.
--    (For SAS/credential-scoped access use a DATABASE SCOPED CREDENTIAL +
--    EXTERNAL DATA SOURCE instead - omitted here since managed identity is
--    cleaner and keeps ADLS public access disabled.)

CREATE DATABASE river_lake;
GO
USE river_lake;
GO
CREATE SCHEMA gold;
GO

-- 3) Logical views over the published parquet (lake/publish/parquet/*.parquet,
--    landed by the pipeline_azure workflow). One logical model, three engines.

CREATE OR ALTER VIEW gold.station_latest AS
SELECT *
FROM OPENROWSET(
    BULK 'https://REPLACE_ACCOUNT.dfs.core.windows.net/lake/publish/parquet/gold_station_latest.parquet',
    FORMAT = 'PARQUET'
) AS r;
GO

CREATE OR ALTER VIEW gold.series AS
SELECT *
FROM OPENROWSET(
    BULK 'https://REPLACE_ACCOUNT.dfs.core.windows.net/lake/publish/parquet/gold_series.parquet',
    FORMAT = 'PARQUET'
) AS r;
GO

-- Silver, so Feature C's bronze->silver->gold trace can be demonstrated in
-- Synapse too (points at the silver parquet the publish step exports).
CREATE OR ALTER VIEW gold.silver_readings AS
SELECT *
FROM OPENROWSET(
    BULK 'https://REPLACE_ACCOUNT.dfs.core.windows.net/lake/publish/parquet/silver.parquet',
    FORMAT = 'PARQUET'
) AS r;
GO

/* Verification - the same shape as the dashboard's headline metric; the
   figures should match gold.json / the live dashboard exactly:
   SELECT station_label, latest_value, change_24h, above_threshold
   FROM gold.station_latest ORDER BY above_threshold DESC; */
