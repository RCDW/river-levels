"""
Publish step: read the built warehouse and emit the artifacts the front-end
serves from the CDN.

  web/data/gold.json        small + fast -> instant first paint (3-second demo)
  web/data/parquet/*.parquet  bronze/silver/gold -> DuckDB-WASM queries these
                              in-browser for Feature C (W7)
  web/data/run_meta.json    last successful run, row counts -> health panel (A)

Only ever runs after `dbt test` passes (see the workflow), so the artifacts
committed are always last-known-good.
"""
from __future__ import annotations

import json
import pathlib

import duckdb

DB = pathlib.Path("data/river.duckdb")
OUT = pathlib.Path("web/data")
PARQUET = OUT / "parquet"


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    PARQUET.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(DB), read_only=True)

    # --- small JSON for first paint -------------------------------------- #
    latest = con.sql("select * from gold_station_latest").df()
    series = con.sql(
        "select station_reference, station_label, date_time_utc, value, reading_id "
        "from gold_series order by date_time_utc"
    ).df()
    series["date_time_utc"] = series["date_time_utc"].astype(str)
    latest["latest_at"] = latest["latest_at"].astype(str)

    gold = {
        "stations": json.loads(latest.to_json(orient="records")),
        "series": json.loads(series.to_json(orient="records")),
    }
    (OUT / "gold.json").write_text(json.dumps(gold, indent=2))

    # --- layer Parquet for DuckDB-WASM (W7 Feature C) -------------------- #
    for layer, query in {
        "gold_series": "select * from gold_series",
        "gold_station_latest": "select * from gold_station_latest",
        "silver": "select * from stg_river_readings",
    }.items():
        con.sql(query).write_parquet(str(PARQUET / f"{layer}.parquet"))

    # --- health panel metadata (Feature A) ------------------------------- #
    rows = con.sql("select count(*) from stg_river_readings").fetchone()[0]
    n_stations = con.sql("select count(*) from gold_station_latest").fetchone()[0]
    n_above = con.sql(
        "select count(*) from gold_station_latest where above_threshold"
    ).fetchone()[0]

    ingest_meta = {}
    p = OUT / "ingest_meta.json"
    if p.exists():
        ingest_meta = json.loads(p.read_text())

    (OUT / "run_meta.json").write_text(
        json.dumps(
            {
                "last_run_utc": ingest_meta.get("last_ingest_utc"),
                "silver_rows": int(rows),
                "stations": int(n_stations),
                "above_threshold": int(n_above),
                "status": "ok",
                "attribution": ingest_meta.get("attribution"),
            },
            indent=2,
        )
    )
    print("[publish] gold.json, parquet/, run_meta.json written")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
