# river-levels: live Environment Agency pipeline & dashboard

[![pipeline](https://img.shields.io/badge/pipeline-live-1d9e75)](https://live.reecewall.dev)
[![status](https://img.shields.io/badge/status-actively%20maintained-0e5b54)]()
[![data](https://img.shields.io/badge/data-Environment%20Agency%20(OGL%20v3.0)-76726b)](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/)

A live [Medallion](https://en.wikipedia.org/wiki/Medallion_architecture) data
pipeline over **Environment Agency** open data for the **River Trent at
Nottingham**, feeding an interactive dashboard. It is the data flagship of the
[reecewall.dev](https://reecewall.dev) portfolio.

- **Dashboard:** https://live.reecewall.dev
- **Design & rationale:** [`ARCHITECTURE.md`](ARCHITECTURE.md) and the decision records in [`docs/adr/`](docs/adr)

<!-- TODO(W8): embed a 15-20s click-to-trace screen capture (GIF) here. Most
     reviewers will not explore the live site; the GIF shows the signature fast. -->
> A click-to-trace demo GIF is coming here. Until then, the live signature is one
> click away at https://live.reecewall.dev: click any chart point.

## What's unusual here

Most pipeline projects show you the *output*. This one makes the **pipeline
itself queryable**. Click any point on the chart and three live in-browser SQL
queries (DuckDB-WASM, over the raw layer Parquet) show that reading as it was
ingested (bronze), cleaned and deduped (silver), and aggregated for the chart
(gold). The normally-invisible 80% of data engineering becomes clickable. This is
the signature feature; a pre-computed `lineage.json` is kept as a graceful
fallback (ADR 0017).

The same gold model is queryable **three ways** from one logical definition:

- **DuckDB-WASM** in the browser (the live trace),
- **DuckDB** at build time (the dbt transform), and
- **Azure Synapse serverless** over the same lake (a showcase query surface).

Same shape as the supply-chain forecasting and replenishment systems I work on:
many sites, live readings, thresholds, forecasting, rivers instead of stores.

## Architecture (hybrid: Azure ingest, free-stack transform and serve)

```
EA real-time API
   │
   ▼  Azure Function (timer)               one shared ea_client core, two runners
ADLS Gen2  lake/bronze/**.parquet          (append-only; reading_id minted here)
   │  ▲              ▲
   │  │ DuckDB (build, azure extension)     reads bronze
   │  │ Synapse serverless external views   read the same lake
   │  │ ADF copy pipeline                   on-demand evidence artifact
   ▼  │
dbt + DuckDB ─▶ SILVER (clean/dedupe/quality flag; table)
            ─▶ GOLD (latest, 24h change, threshold, series, forecast)
   │  publish (Python)
   ▼
gold.json + layer Parquet + run_meta.json
   │  scheduled pipeline self-publishes (scoped aws s3 sync + /data/* invalidation)
   ▼
AWS S3 + CloudFront  ─▶  static dashboard (DuckDB-WASM in-browser trace)
```

Azure is used where it earns its place (durable cloud landing, file-arrival
monitoring, serverless query); dbt + DuckDB where it is the better fit for a
live, free, public project (transform, serve, in-browser query). See
[Azure equivalence](#azure-equivalence) for the mapping to a pure-Azure build,
and [`docs/w6-cutover-runbook.md`](docs/w6-cutover-runbook.md) for the hybrid
cutover playbook.

The trace key, **`reading_id` = `md5(measure|dateTime)`, is minted once at
ingest** and carried unchanged through bronze, silver and gold. That, plus an
append-only bronze and a materialised silver, is what keeps every layer
independently queryable, which is the basis for the click-to-trace feature.

## Decision log (why, not just what)

The load-bearing choices, each recorded in full under [`docs/adr/`](docs/adr)
(ADR set 0001 to 0020):

- **Hybrid stack, not pure-Azure** (ADR 0009, 0014). The CV already evidences
  Azure; the portfolio adds the modern free stack and closes named gaps (dbt,
  Medallion, a non-Microsoft warehouse, CI-for-data). Azure still does
  ingest, landing, monitoring and serverless query, so the cloud story is real,
  chosen tool by tool.
- **`reading_id` minted at ingest, asserted not re-derived** (ADR 0012). One md5
  surrogate over `(measure, dateTime)` threads through every layer, so the trace
  is an exact join rather than a re-derived key that could drift between a raw
  string timestamp and a typed one.
- **Bronze append-only; silver materialised as a table** (ADR 0008). Costs a
  little storage; buys per-record lineage, the reason the trace is possible.
- **Last-known-good by construction** (ADR 0011). Publish only runs after
  `dbt test` passes, so a failed run never overwrites good artifacts. The `data`
  branch is the durable record.
- **The pipeline self-publishes fresh data to the edge** (ADR 0018). S3 +
  CloudFront has no git-push-to-deploy, so the scheduled run assumes a dedicated
  least-privilege OIDC role and runs a scoped `aws s3 sync` of `web/data` plus a
  `/data/*` invalidation. The freshness badge now reflects the last pipeline run,
  not the last code deploy.
- **Forecast is a deliberate simple trend** (ADR 0019): a damped linear fit over
  the last 12h, default off, labelled in-UI. Honest about its limit: rivers
  respond to upstream rainfall, which it does not model. That gap is the "small
  changes propagate downstream" interview hook, and a clear next step.
- **Cross-origin nav to the hub** (ADR 0020). The dashboard nav links absolutely
  to `reecewall.dev`, sharing brand tokens and favicon so the two origins read as
  one site.

The real lineage is the dbt DAG itself: run `dbt docs generate` in `transform/`
and open `target/index.html` to browse the model graph and tests.

## Cost (honest)

Effectively free, not zero. Functions sit inside the free grant; ADLS Gen2 and
the Function's storage account are a few pence per month; Synapse serverless is
charged per TB processed at MB-scale, with a data-processed budget cap; ADF runs
on-demand only. **Roughly £0.20 to £0.50 per month**, budget-capped.

## Security posture

See [`SECURITY.md`](SECURITY.md). In short: no public ingress (timer-only
Function), no stored secrets (OIDC + managed identity), a private lake,
read-only public artifacts of already-public data, a least-privilege publish
role (`<domain>-gha-data-publish`), and pinned dependencies with an OSV gate.

## Run locally

```bash
pip install -r ingest/requirements.txt -r requirements-dev.txt
python -m ingest.run_ingest --discover   # find Trent station refs (run once)
python -m ingest.run_ingest              # ingest -> bronze parquet
cd transform && dbt deps && dbt seed && dbt run && dbt test && cd ..
python publish/export.py                 # gold.json + parquet + run_meta
python -m http.server -d web 8000        # range requests need a real server
```

The pinned stations live in [`config/stations.yml`](config/stations.yml)
(discovered against the live API, not hard-coded).

## Layout

```
ingest/            EA API client (shared core) + the Actions entrypoint
azure_function/    Azure Function (timer): same core, lands bronze in ADLS
transform/         dbt project: bronze source -> silver -> gold + tests
publish/           gold -> gold.json (+forecast) + layer parquet + run_meta
web/               static dashboard (index.html, tokens.css, favicon.svg; WASM trace)
synapse/           serverless external views (the showcase query surface)
adf/               on-demand Copy pipeline (ADF evidence artifact)
infra/             AWS Terraform; infra/azure/ is the Azure module (separate state)
config/            stations.yml: the pinned Trent stations
docs/              ADRs (docs/adr/) + the W6 cutover runbook
.github/workflows/ ci, deploy, infra, pipeline_azure, security-scan (+ disabled W3 rollback)
```

## Known limitations and what's next

- Live readings span roughly four weeks; deeper history accumulates in bronze or
  would be backfilled from the EA daily archive CSVs.
- The forecast is univariate (ADR 0019); rainfall-as-a-feature is the planned
  upgrade and the most honest next step.
- Roadmap: rainfall feature, a pipeline-runs history page, rolling z-score anomaly
  detection, dbt model contracts and an exposure.

## Azure equivalence

| This build | Pure-Azure equivalent |
|---|---|
| Python ingest -> bronze | ADF copy -> ADLS landing |
| dbt models | Databricks notebooks (PySpark / Spark SQL) + Synapse |
| dbt tests | pipeline data-quality checks |
| DuckDB | Synapse serverless |
| GitHub Actions cron | ADF / Synapse triggers |

## Attribution & licence

Code: MIT (see [`LICENSE`](LICENSE)). Data: this uses Environment Agency flood and
river level data from the real-time data API (Beta), under the
[Open Government Licence v3.0](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/).
