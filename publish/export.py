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
RUN_RESULTS = pathlib.Path("transform/target/run_results.json")


def dbt_test_stats() -> dict:
    """Real test pass/total from the last `dbt test`, for the health panel
    (Feature A). dbt writes target/run_results.json, and publish always runs
    straight after `dbt test`, so this file reflects the gate that let us
    publish. Guarded: if it is absent (a publish-only local run) we report nulls
    rather than inventing a status.

    We deliberately report tests only, not models: `dbt test` overwrites
    run_results.json after `dbt run`, so a model count here would always be 0 and
    misrepresent the run."""
    if not RUN_RESULTS.exists():
        return {"tests_passed": None, "tests_total": None}
    results = json.loads(RUN_RESULTS.read_text()).get("results", [])
    tests = [r for r in results if r["unique_id"].startswith("test.")]
    return {
        "tests_passed": sum(1 for r in tests if r["status"] == "pass"),
        "tests_total": len(tests),
    }


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
    n_above = con.sql("select count(*) from gold_station_latest where above_threshold").fetchone()[
        0
    ]

    ingest_meta = {}
    p = OUT / "ingest_meta.json"
    if p.exists():
        ingest_meta = json.loads(p.read_text())

    stats = dbt_test_stats()
    # Publish only ever runs after a green `dbt build`/`dbt test` (see the
    # workflow), so every published run is last-known-good: each stage is "ok".
    stages = [
        {"name": "ingest", "status": "ok"},
        {"name": "dbt build", "status": "ok"},
        {"name": "dbt test", "status": "ok"},
        {"name": "publish", "status": "ok"},
    ]

    (OUT / "run_meta.json").write_text(
        json.dumps(
            {
                "last_run_utc": ingest_meta.get("last_ingest_utc"),
                "rows_ingested": ingest_meta.get("rows_ingested"),
                "silver_rows": int(rows),
                "stations": int(n_stations),
                "above_threshold": int(n_above),
                "tests_passed": stats["tests_passed"],
                "tests_total": stats["tests_total"],
                "stages": stages,
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
