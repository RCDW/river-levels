"""
W6 hybrid migration target. Same ingest *logic* as the GitHub Actions path,
it imports the identical ea_client core, but runs on a timer in Azure and
lands bronze Parquet in Azure Blob Storage (mirrors the Boots "files land in
Blob on time" monitoring story).

Consumption plan: timer executions sit within the free monthly grant.
Set app settings: BLOB_CONN_STR, BRONZE_CONTAINER (e.g. "bronze").
"""
import datetime as dt
import io
import json
import logging
import os

import azure.functions as func
import pandas as pd
import yaml
from azure.storage.blob import BlobServiceClient

# the SAME core used by run_ingest.py, one ingest implementation, two runners
from ingest import ea_client as ea


def _load_station_refs() -> list[str]:
    cfg = yaml.safe_load(open(os.path.join(os.path.dirname(__file__), "..", "config", "stations.yml")))
    return [s["station_reference"] for s in cfg["stations"]]


def main(timer: func.TimerRequest) -> None:
    run_ts = ea.utc_now_iso()
    refs = _load_station_refs()
    since = ea.since_hours_ago(6)
    rows = ea.fetch_many(refs, since)

    if not rows:
        logging.info("No new readings since %s", since)
        return

    df = pd.DataFrame(rows)
    df["_ingested_at"] = run_ts
    df["_source_batch_id"] = run_ts

    bsc = BlobServiceClient.from_connection_string(os.environ["BLOB_CONN_STR"])
    container = os.environ.get("BRONZE_CONTAINER", "bronze")
    day = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d")
    blob_path = f"bronze/dt={day}/batch_{run_ts.replace(':', '').replace('-', '')}.parquet"

    buf = io.BytesIO()
    df.to_parquet(buf, index=False)
    buf.seek(0)
    bsc.get_container_client(container).upload_blob(blob_path, buf, overwrite=False)

    # file-arrival heartbeat (the monitoring story): write a tiny manifest blob
    manifest = {"last_ingest_utc": run_ts, "rows": len(df), "blob": blob_path}
    bsc.get_container_client(container).upload_blob(
        "bronze/_latest.json", json.dumps(manifest), overwrite=True
    )
    logging.info("Landed %d rows -> %s", len(df), blob_path)
