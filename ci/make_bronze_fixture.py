"""Generate a tiny, deterministic bronze fixture for CI.

The CI gate runs ``dbt build`` + ``dbt test`` to prove the transform layer
produces a queryable, tested artifact (the data analog of a smoke test). It must
not depend on the live EA API, so this writes a handful of representative
readings, matching the bronze schema with ``reading_id`` minted exactly as
ingest does, into ``data/bronze/``. Timestamps are relative to now so the rows
fall inside the gold 30-day / 24h-change windows.
"""

from __future__ import annotations

import datetime as dt
import pathlib

import pandas as pd

from ingest.ea_client import mint_reading_id

BRONZE = pathlib.Path("data/bronze")
STATIONS = [("4009", "Colwick"), ("4126", "Clifton Bridge")]


def main() -> int:
    now = dt.datetime.now(dt.UTC).replace(microsecond=0)
    run_ts = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    rows = []
    for ref, label in STATIONS:
        measure = (
            "http://environment.data.gov.uk/flood-monitoring/id/measures/"
            f"{ref}-level-stage-i-15_min-mASD"
        )
        # now, 24h ago, 48h ago: exercises latest, 24h-change and the series.
        for i, hours in enumerate([0, 24, 48]):
            ts = (now - dt.timedelta(hours=hours)).strftime("%Y-%m-%dT%H:%M:%SZ")
            rows.append(
                {
                    "reading_id": mint_reading_id(measure, ts),
                    "measure": measure,
                    "station_reference": ref,
                    "station_label": label,
                    "parameter": "level",
                    "qualifier": "Stage",
                    "unit_name": "mASD",
                    "date_time": ts,
                    "value": 1.0 + 0.1 * i,
                    "_ingested_at": run_ts,
                    "_source_batch_id": run_ts,
                }
            )

    out = BRONZE / f"dt={now:%Y-%m-%d}"
    out.mkdir(parents=True, exist_ok=True)
    target = out / "ci_fixture.parquet"
    pd.DataFrame(rows).to_parquet(target, index=False)
    print(f"[fixture] wrote {len(rows)} rows -> {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
