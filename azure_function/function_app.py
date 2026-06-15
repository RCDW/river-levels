"""
W6 ingest path - Azure Functions Python v2 programming model.

Single file, decorator-based (no function.json). Runs on a timer on the
Consumption plan (inside the free monthly grant) and lands append-only bronze
Parquet in ADLS Gen2. Imports the SAME ``ingest.ea_client`` core used by the
GitHub Actions path - one ingest implementation, two runners (ADR 0010). The
trace key (``reading_id``) is minted in that shared core (ADR 0012), so it is
identical whichever runner produced the data.

Auth: managed identity (DefaultAzureCredential). Assign the Function's identity
the 'Storage Blob Data Contributor' role on the storage account - no secrets in
code. Falls back to a connection string only if AZURE_STORAGE_CONNECTION_STRING
is set (handy for local `func start`).

App settings to configure:
    LAKE_ACCOUNT_URL   = https://<account>.blob.core.windows.net
    LAKE_CONTAINER     = lake
    (optional) STATIONS_CONFIG  = explicit path to stations.yml
    (optional) AZURE_STORAGE_CONNECTION_STRING for local dev

Deployment note: the deployment package must include the repo's ``ingest/``
package (so ``from ingest import ea_client`` resolves) and ``config/stations.yml``.
See docs/w6-cutover-runbook.md for the exact packaging/publish steps.
"""

import datetime as dt
import io
import json
import logging
import os

import azure.functions as func
import pandas as pd
import yaml
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

# the SAME core used by run_ingest.py - one ingest implementation, two runners
from ingest import ea_client as ea

app = func.FunctionApp()


def _blob_service() -> BlobServiceClient:
    """Managed identity by default; connection-string fallback for local dev."""
    conn = os.environ.get("AZURE_STORAGE_CONNECTION_STRING")
    if conn:
        return BlobServiceClient.from_connection_string(conn)
    return BlobServiceClient(
        account_url=os.environ["LAKE_ACCOUNT_URL"],
        credential=DefaultAzureCredential(),
    )


def _station_refs() -> list[str]:
    """Read the pinned stations. Looks (in order) at STATIONS_CONFIG, a copy
    vendored alongside the function, then the repo-root layout - so it works
    whether config/ is co-deployed inside the function or kept at the root."""
    here = os.path.dirname(__file__)
    candidates = [
        os.environ.get("STATIONS_CONFIG"),
        os.path.join(here, "config", "stations.yml"),
        os.path.join(here, "..", "config", "stations.yml"),
    ]
    for path in candidates:
        if path and os.path.exists(path):
            with open(path) as fh:
                cfg = yaml.safe_load(fh)
            return [s["station_reference"] for s in cfg["stations"]]
    raise FileNotFoundError(
        "stations.yml not found; set STATIONS_CONFIG or co-deploy config/stations.yml"
    )


@app.timer_trigger(
    schedule="0 0 */3 * * *",  # every 3 hours (NCRONTAB: sec min hour day month dow)
    arg_name="timer",
    run_on_startup=False,
    use_monitor=True,
)
def river_ingest(timer: func.TimerRequest) -> None:
    run_ts = ea.utc_now_iso()
    if timer.past_due:
        logging.warning("Timer is past due; running anyway at %s", run_ts)

    refs = _station_refs()
    since = ea.since_hours_ago(6)
    rows = ea.fetch_many(refs, since)
    if not rows:
        logging.info("No new readings since %s", since)
        return

    df = pd.DataFrame(rows)
    df["_ingested_at"] = run_ts
    df["_source_batch_id"] = run_ts

    buf = io.BytesIO()
    df.to_parquet(buf, index=False)
    buf.seek(0)

    # Partition by run day. Unlike the Actions runner (which partitions by the
    # reading's own date), this lumps a batch into the run-day folder - harmless,
    # because silver globs every bronze file (union_by_name) and dedupes on
    # reading_id, so layout never affects correctness. Run-day also keeps the
    # "a file landed today" monitoring story simple.
    container = os.environ.get("LAKE_CONTAINER", "lake")
    day = dt.datetime.now(dt.UTC).strftime("%Y-%m-%d")
    blob_path = f"bronze/dt={day}/batch_{run_ts.replace(':', '').replace('-', '')}.parquet"

    cc = _blob_service().get_container_client(container)
    cc.upload_blob(blob_path, buf, overwrite=False)  # append-only: never overwrite

    # File-arrival heartbeat - the "files land on time" monitoring story. A
    # separate check can alert if _latest.json goes stale (no fresh landing).
    cc.upload_blob(
        "bronze/_latest.json",
        json.dumps({"last_ingest_utc": run_ts, "rows": len(df), "blob": blob_path}),
        overwrite=True,
    )
    logging.info("Landed %d rows -> %s/%s", len(df), container, blob_path)
