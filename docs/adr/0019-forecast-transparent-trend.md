# 19. Forecast is a transparent damped linear trend

- **Status:** Accepted
- **Date:** 2026-06-15

## Context

W7 Feature D adds a forecast overlay to the chart. A real river-level forecast is
a hydrological model: it needs upstream rainfall, catchment routing, antecedent
conditions. This is a portfolio data pipeline, not a forecasting service, and the
honesty principle forbids presenting something as a real model when it is not. We
want a projection that is useful to look at, cheap to compute inside the existing
publish step, and that can be explained line by line.

## Decision

Compute a least-squares **linear trend over the last 12h** of gold readings per
station, **lightly damped** (`0.97 ** k` per 15-minute step) so the projection
eases out over the 6h horizon rather than extrapolating a straight line, and
embed it in `gold.json` as a per-station array plus a `forecast_method` string.
It is computed in `publish/export.py` with numpy; the toggle (default off) shows
a dashed line and the UI states the limitation outright: univariate, rainfall not
modelled.

The windows and damping factor live as named constants (`FIT_HOURS`,
`FORECAST_HOURS`, `STEP_MIN`, and the `0.97` damp) so they are easy to revisit.

Alternatives considered: no forecast (loses the hook and the statistical nod);
a heavier model (dishonest for the data we hold, and out of scope for W7).

## Consequences

- **+** Cheap, deterministic, recomputed every run from the same warehouse; no
  extra service or model artifact to host.
- **+** Honest and explainable. The gap (rainfall drives river rise; this models
  none of it) is stated in-UI and is itself the "small changes propagate
  downstream" interview hook, not a flaw to hide.
- **+** The forecast rides the existing publish + self-publish path (ADR 0018),
  so it refreshes on the pipeline's schedule like every other artifact.
- **-** Univariate and short-horizon: it is wrong precisely when a rainfall event
  drives a step change. That is the point, and the UI says so.
- **-** Adds numpy to the publish runtime. It was already a pinned dev dependency
  (`requirements-dev.txt`); this only adds it to the pipeline install.
- **-** The damping and windows are tuned by eye, not validated against held-out
  data. Acceptable for a transparent trend; the named constants make tuning or
  removal a one-line change.
