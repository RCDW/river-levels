"""
Publish step: read the built warehouse and emit the artifacts the front-end
serves from the CDN.

  web/data/gold.json        small + fast -> instant first paint (3-second demo);
                            also carries the per-station forecast (Feature D)
  web/data/parquet/*.parquet  bronze/silver/gold -> DuckDB-WASM queries these
                              in-browser for Feature C (W7). Bronze is a rolling
                              window so the trace reaches the raw layer cheaply.
  web/data/run_meta.json    last successful run, row counts -> health panel (A)

Only ever runs after `dbt test` passes (see the workflow), so the artifacts
committed are always last-known-good.
"""

from __future__ import annotations

import json
import os
import pathlib

import duckdb
import numpy as np

DB = pathlib.Path("data/river.duckdb")
OUT = pathlib.Path("web/data")
PARQUET = OUT / "parquet"
RUN_RESULTS = pathlib.Path("transform/target/run_results.json")
# Feature C traces back to the raw layer in-browser, but bronze is append-only
# and grows forever; export only a rolling window so bronze.parquet stays small
# (and free) while still covering the plotted range. 90 days is well past the
# 30-day gold window the chart shows.
WINDOW_DAYS = 90
# Feature D forecast shape: fit the trend on the last FIT_HOURS, project
# FORECAST_HOURS ahead at the EA reading cadence.
FORECAST_HOURS = 6
FIT_HOURS = 12
STEP_MIN = 15
# Bronze stays external Parquet (never collapsed into the db) so it can be queried
# as its own layer. Matches transform/models/sources.yml; publish runs from the
# repo root, hence the root-relative default. W6 swaps this for an Azure Blob URL.
BRONZE_GLOB = os.environ.get("BRONZE_GLOB", "data/bronze/**/*.parquet")
# EA attribution is required wherever the data is shown (OGL v3). It is fixed
# text, not run-dependent, so always emit it - never let it fall to null (the
# hybrid path has no local ingest_meta.json to read it from).
ATTRIBUTION = (
    "this uses Environment Agency flood and river level data from the real-time data API (Beta)"
)


def _enable_azure_if_needed(con: duckdb.DuckDBPyConnection) -> None:
    """When BRONZE_GLOB points at the lake (the azure pipeline), the lineage
    step re-reads bronze straight from ADLS. This standalone connection needs
    the azure extension + a credential to do that; the local dev path needs
    neither, so this is a no-op unless the glob is an Azure URL. Auth is the
    same passwordless credential_chain the dbt azure target uses."""
    if not BRONZE_GLOB.startswith(("abfss://", "az://", "azure://")):
        return
    con.execute("INSTALL azure; LOAD azure;")
    con.execute(
        "CREATE SECRET IF NOT EXISTS azlake "
        "(TYPE azure, PROVIDER credential_chain, "
        "CHAIN 'cli;managed_identity;env', "
        f"ACCOUNT_NAME '{os.environ['LAKE_ACCOUNT_NAME']}')"
    )


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


def emit_lineage(con: duckdb.DuckDBPyConnection) -> None:
    """Pre-computed bronze -> silver -> gold lineage for every plotted reading_id
    (Feature C v1). Keyed by reading_id, the trace key minted at ingest and
    carried unchanged, never re-derived here. Each layer is queried independently:
    bronze straight from the append-only Parquet, silver and gold from their
    tables, so the dedup story (bronze may hold >1 copy; silver kept the latest)
    is real, not asserted.

    The payload shape is exactly what W7 will reproduce from a live DuckDB-WASM
    query, so that upgrade swaps the *source*, not the front-end."""
    gold = con.sql(
        "select reading_id, station_reference, station_label, "
        "date_time_utc, value, unit_name from gold_series"
    ).df()
    gold["date_time_utc"] = gold["date_time_utc"].astype(str)

    silver = con.sql(
        "select reading_id, value, quality_flag, ingested_at "
        "from stg_river_readings "
        "where reading_id in (select reading_id from gold_series)"
    ).df()
    silver["ingested_at"] = silver["ingested_at"].astype(str)
    silver_by_id = {r["reading_id"]: r for r in json.loads(silver.to_json(orient="records"))}

    # Raw copies per reading_id, oldest first; exposes the normally-invisible
    # duplicate ingests that silver dedupes away.
    bronze = con.sql(
        "select b.reading_id, b.value, b._ingested_at as ingested_at, "
        "b._source_batch_id as source_batch_id "
        f"from read_parquet('{BRONZE_GLOB}', union_by_name=true, filename=true) b "
        "where b.reading_id in (select reading_id from gold_series) "
        "order by b.reading_id, b._ingested_at"
    ).df()
    bronze_by_id: dict[str, list] = {}
    for rec in json.loads(bronze.to_json(orient="records")):
        bronze_by_id.setdefault(rec["reading_id"], []).append(
            {
                "value": rec["value"],
                "ingested_at": rec["ingested_at"],
                "source_batch_id": rec["source_batch_id"],
            }
        )

    lineage = {}
    for g in json.loads(gold.to_json(orient="records")):
        rid = g["reading_id"]
        copies = bronze_by_id.get(rid, [])
        s = silver_by_id.get(rid)
        lineage[rid] = {
            "reading_id": rid,
            "station_reference": g["station_reference"],
            "station_label": g["station_label"],
            "date_time_utc": g["date_time_utc"],
            "bronze": {"copies": len(copies), "records": copies},
            "silver": (
                {
                    "value": s["value"],
                    "quality_flag": s["quality_flag"],
                    "ingested_at": s["ingested_at"],
                }
                if s
                else None
            ),
            "gold": {"value": g["value"], "unit_name": g["unit_name"]},
        }

    (OUT / "lineage.json").write_text(json.dumps(lineage))
    print(f"[publish] lineage.json written ({len(lineage)} readings)")


def _forecast(series_rows: list[dict]) -> list[dict]:
    """Feature D: a deliberately simple, explainable forecast. Least-squares
    linear trend fit on the last FIT_HOURS of readings, lightly damped, projected
    FORECAST_HOURS past the latest point at the EA cadence.

    Univariate on purpose: a real river forecast needs upstream rainfall as a
    feature, and this models none. That honest limitation is the "small changes
    propagate downstream" story the UI states outright; it is not dressed up as a
    real model. Returns [] when there is too little recent data to fit."""
    pts = [r for r in series_rows if r["value"] is not None]
    if len(pts) < 4:
        return []
    t0 = np.array([np.datetime64(r["date_time_utc"]) for r in pts])
    secs = (t0 - t0[0]) / np.timedelta64(1, "s")
    recent = secs >= (secs.max() - FIT_HOURS * 3600)
    if recent.sum() < 4:
        return []
    x, y = secs[recent], np.array([r["value"] for r in pts])[recent]
    slope, _intercept = np.polyfit(x, y, 1)
    last_v = pts[-1]["value"]
    out = []
    steps = int(FORECAST_HOURS * 60 / STEP_MIN)
    for k in range(1, steps + 1):
        ds = k * STEP_MIN * 60
        damp = 0.97**k  # ease the slope out over the horizon, never extrapolate hard
        v = last_v + slope * ds * damp
        ts = np.datetime64(pts[-1]["date_time_utc"]) + np.timedelta64(ds, "s")
        out.append({"date_time_utc": str(ts), "value": round(float(v), 3), "kind": "forecast"})
    return out


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    PARQUET.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(DB), read_only=True)
    _enable_azure_if_needed(con)

    # --- small JSON for first paint -------------------------------------- #
    latest = con.sql("select * from gold_station_latest").df()
    series = con.sql(
        "select station_reference, station_label, date_time_utc, value, reading_id "
        "from gold_series order by date_time_utc"
    ).df()
    series["date_time_utc"] = series["date_time_utc"].astype(str)
    latest["latest_at"] = latest["latest_at"].astype(str)

    series_records = json.loads(series.to_json(orient="records"))
    by_station: dict[str, list[dict]] = {}
    for r in series_records:
        by_station.setdefault(r["station_reference"], []).append(r)

    gold = {
        "stations": json.loads(latest.to_json(orient="records")),
        "series": series_records,
        # Feature D: per-station projection + the method string the UI shows so
        # the forecast is never mistaken for more than a transparent trend.
        "forecast": {ref: _forecast(rows) for ref, rows in by_station.items()},
        "forecast_method": "linear trend (last 12h, damped); univariate, rainfall not modelled",
    }
    (OUT / "gold.json").write_text(json.dumps(gold, indent=2))

    # --- layer Parquet for DuckDB-WASM (W7 Feature C) -------------------- #
    for layer, query in {
        "gold_series": "select * from gold_series",
        "gold_station_latest": "select * from gold_station_latest",
        "silver": "select * from stg_river_readings",
    }.items():
        con.sql(query).write_parquet(str(PARQUET / f"{layer}.parquet"))
    # Bronze is the append-only raw layer, read straight from its Parquet (never
    # collapsed into the db), so the trace can show the real duplicate ingests.
    # Export only the rolling window to keep the file small; the same date_time
    # column drives the silver cast (transform/models/sources.yml).
    con.sql(
        f"select * from read_parquet('{BRONZE_GLOB}', union_by_name=true) "
        f"where cast(date_time as timestamp) >= now() - interval {WINDOW_DAYS} day"
    ).write_parquet(str(PARQUET / "bronze.parquet"))

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
                "attribution": ATTRIBUTION,
            },
            indent=2,
        )
    )
    # --- pre-computed click-to-trace lineage (Feature C v1) -------------- #
    emit_lineage(con)

    print("[publish] gold.json (+forecast), parquet/ (incl bronze window), run_meta.json written")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
