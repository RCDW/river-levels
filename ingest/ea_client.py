"""
Environment Agency real-time flood-monitoring API client.

This is the SINGLE source of ingest logic. It is deliberately framework-free
so it can be called identically from:
  - GitHub Actions (W3, via run_ingest.py)
  - an Azure Function timer trigger (W6, via azure_function/)

API reference: https://environment.data.gov.uk/flood-monitoring/doc/reference
Open Government Licence v3.0. Attribution required:
  "this uses Environment Agency flood and river level data from the real-time data API (Beta)"
"""
from __future__ import annotations

import datetime as dt
import hashlib
from dataclasses import dataclass, asdict
from typing import Iterable

import requests

ROOT = "https://environment.data.gov.uk/flood-monitoring"
ATTRIBUTION = (
    "this uses Environment Agency flood and river level data "
    "from the real-time data API (Beta)"
)
_SESSION = requests.Session()
_SESSION.headers.update({"User-Agent": "reecewall.dev river-portfolio (contact: rcdwall@gmail.com)"})


def _get(url: str, params: dict | None = None) -> dict:
    # The API may redirect under load; requests follows redirects by default.
    resp = _SESSION.get(url, params=params, timeout=30)
    resp.raise_for_status()
    return resp.json()


# --------------------------------------------------------------------------- #
# Station discovery (run once; result is pinned into config/stations.yml)
# --------------------------------------------------------------------------- #
def discover_stations(search: str = "Trent", town: str | None = None) -> list[dict]:
    """
    Find candidate stations. NOTE: `riverName` is an EXACT match and the EA's
    own examples use bare names (e.g. 'Cherwell'), so we lead with the fuzzy
    `search` (label contains) filter and let you eyeball the results, rather
    than guessing whether the value is 'Trent' or 'River Trent'.
    """
    params: dict = {"search": search, "_view": "full"}
    if town:
        params = {"town": town, "_view": "full"}
    items = _get(f"{ROOT}/id/stations", params).get("items", [])
    out = []
    for s in items:
        scale = s.get("stageScale") or {}
        out.append(
            {
                "station_reference": s.get("stationReference"),
                "station_label": s.get("label"),
                "river_name": s.get("riverName"),
                "town": s.get("town"),
                "lat": s.get("lat"),
                "long": s.get("long"),
                "status": s.get("status"),
                # typicalRangeHigh = level exceeded only ~5% of the time on record:
                # a sensible *data-driven* default anomaly threshold (Feature B).
                "typical_range_high": (scale.get("typicalRangeHigh") if isinstance(scale, dict) else None),
            }
        )
    return out


# --------------------------------------------------------------------------- #
# Readings ingest (the scheduled path)
# --------------------------------------------------------------------------- #
def mint_reading_id(measure: str | None, date_time: str | None) -> str:
    """The trace key. Minted ONCE here at ingest as md5(measure|dateTime) and
    carried UNCHANGED through bronze -> silver -> gold (it is what makes
    Feature C, click-to-trace, exact). Never regenerate it downstream."""
    return hashlib.md5(f"{measure}|{date_time}".encode("utf-8")).hexdigest()


@dataclass
class Reading:
    # Natural key of a reading is (measure, date_time). The measure URI encodes
    # station + parameter + qualifier + interval + unit, so it is stable.
    reading_id: str         # md5(measure|date_time), minted here, carried unchanged
    measure: str
    station_reference: str | None
    station_label: str | None
    parameter: str | None
    qualifier: str | None
    unit_name: str | None
    date_time: str          # ISO8601, as returned
    value: float | None     # None when the API omits it (NaN readings)


def fetch_station_readings(station_reference: str, since_iso: str, limit: int = 10000) -> list[Reading]:
    """
    Pull readings for one station since `since_iso` (exclusive), newest first.
    `_view=full` inlines the measure description + station label so a single
    call yields everything bronze needs, no second metadata round-trip.
    """
    url = f"{ROOT}/id/stations/{station_reference}/readings"
    params = {"since": since_iso, "_sorted": "", "_view": "full", "_limit": limit}
    items = _get(url, params).get("items", [])
    readings: list[Reading] = []
    for r in items:
        measure = r.get("measure")
        # With _view=full, `measure` is an object; without it, a bare URI string.
        if isinstance(measure, dict):
            m_uri = measure.get("@id")
            parameter = measure.get("parameter")
            qualifier = measure.get("qualifier")
            unit_name = measure.get("unitName")
            station_ref = measure.get("stationReference") or station_reference
            station = measure.get("station")
            station_label = station.get("label") if isinstance(station, dict) else None
        else:
            m_uri = measure
            parameter = qualifier = unit_name = station_label = None
            station_ref = station_reference
        date_time = r.get("dateTime")
        readings.append(
            Reading(
                reading_id=mint_reading_id(m_uri, date_time),
                measure=m_uri,
                station_reference=station_ref,
                station_label=station_label,
                parameter=parameter,
                qualifier=qualifier,
                unit_name=unit_name,
                date_time=date_time,
                value=r.get("value"),  # absent for NaN -> None -> silver flags 'missing'
            )
        )
    return readings


def fetch_many(station_refs: Iterable[str], since_iso: str) -> list[dict]:
    rows: list[dict] = []
    for ref in station_refs:
        for reading in fetch_station_readings(ref, since_iso):
            rows.append(asdict(reading))
    return rows


def utc_now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def since_hours_ago(hours: int) -> str:
    t = dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=hours)
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")
