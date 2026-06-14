# river-levels

A live [Medallion](https://en.wikipedia.org/wiki/Medallion_architecture) data
pipeline over **Environment Agency** open data for the **River Trent at
Nottingham**, feeding an interactive dashboard. It is the data flagship of the
[reecewall.dev](https://reecewall.dev) portfolio.

- **Dashboard:** https://live.reecewall.dev
- **Design & rationale:** [`ARCHITECTURE.md`](ARCHITECTURE.md) · decision records in [`docs/adr/`](docs/adr)

> **Status: not yet live.** Initialisation is in progress (the W1-W3
> milestones: pin real stations, then tested bronze/silver/gold, then a
> deployed dashboard). Azure (Function + Blob) is a later milestone and
> deliberately out of scope for now. The forecast, when it lands, is a simple
> linear trend, not a hydrological model. Honest about what it is.

## Pipeline

```
EA real-time API → ingest (Python) → BRONZE  (append-only Parquet)
                                       │ dbt + DuckDB
                                       ▼
                                     SILVER  (clean / dedupe / quality flag; table)
                                       │ dbt
                                       ▼
                                     GOLD    (latest, 24h change, threshold, series)
                                       │ publish (Python)
                                       ▼
                        gold.json + layer Parquet + run_meta.json → static dashboard
```

The trace key, **`reading_id` = `md5(measure|dateTime)`, is minted once at
ingest** and carried unchanged through bronze → silver → gold. That, plus an
append-only bronze and a materialised silver, is what keeps every layer
independently queryable, which is the basis for the click-to-trace feature.

## Run locally

```bash
pip install -r ingest/requirements.txt && pip install dbt-duckdb duckdb numpy
python -m ingest.run_ingest --discover   # find Trent station refs (run once)
python -m ingest.run_ingest              # ingest -> bronze parquet
cd transform && dbt deps && dbt seed && dbt run && dbt test && cd ..
python publish/export.py                 # gold.json + parquet + run_meta
python -m http.server -d web 8000        # range requests need a real server
```

The pinned stations live in [`config/stations.yml`](config/stations.yml)
(discovered against the live API, not hard-coded).

## Attribution

This uses Environment Agency flood and river level data from the real-time data
API (Beta), under the [Open Government Licence v3.0](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/).
