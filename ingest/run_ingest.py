"""
Ingest entrypoint for the GitHub Actions path (W3).

Writes BRONZE as append-only Parquet partitions:
    data/bronze/dt=YYYY-MM-DD/batch_<utc_ts>.parquet

Bronze is NEVER overwritten; this is the decision that keeps Feature C
(click-to-trace bronze -> silver -> gold) possible. Each run adds a new file;
silver later dedupes on reading_id keeping the latest _ingested_at.

Usage:
    python -m ingest.run_ingest                 # incremental (lookback window)
    python -m ingest.run_ingest --hours 48      # custom backfill window
    python -m ingest.run_ingest --discover      # print candidate stations & exit
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

import pandas as pd
import yaml

from ingest import ea_client as ea

CONFIG = pathlib.Path("config/stations.yml")
BRONZE_DIR = pathlib.Path("data/bronze")
META_DIR = pathlib.Path("web/data")


def load_config() -> dict:
    return yaml.safe_load(CONFIG.read_text())


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--hours", type=int, default=None, help="lookback window in hours")
    ap.add_argument("--discover", action="store_true", help="list candidate stations and exit")
    args = ap.parse_args(argv)

    if args.discover:
        for s in ea.discover_stations(search="Trent"):
            print(json.dumps(s, ensure_ascii=False))
        return 0

    cfg = load_config()
    refs = [s["station_reference"] for s in cfg["stations"]]
    lookback = args.hours or cfg.get("lookback_hours", 6)
    since = ea.since_hours_ago(lookback)

    rows = ea.fetch_many(refs, since)
    run_ts = ea.utc_now_iso()
    df = pd.DataFrame(rows)
    if df.empty:
        print(f"[ingest] no new readings since {since}", file=sys.stderr)
    else:
        df["_ingested_at"] = run_ts
        df["_source_batch_id"] = run_ts
        df["_dt"] = pd.to_datetime(df["date_time"]).dt.strftime("%Y-%m-%d")
        for day, part in df.groupby("_dt"):
            out_dir = BRONZE_DIR / f"dt={day}"
            out_dir.mkdir(parents=True, exist_ok=True)
            fname = out_dir / f"batch_{run_ts.replace(':', '').replace('-', '')}.parquet"
            part.drop(columns=["_dt"]).to_parquet(fname, index=False)
            print(f"[ingest] wrote {len(part)} rows -> {fname}")

    # Run metadata for the health panel (Feature A). Written every run.
    META_DIR.mkdir(parents=True, exist_ok=True)
    (META_DIR / "ingest_meta.json").write_text(
        json.dumps(
            {
                "last_ingest_utc": run_ts,
                "since": since,
                "rows_ingested": int(len(df)),
                "stations": len(refs),
                "attribution": ea.ATTRIBUTION,
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
