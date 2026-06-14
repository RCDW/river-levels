# 6. Guarding the react/react-dom major-mismatch class

- **Status:** Accepted
- **Date:** 2026-06-12

## Context

A Dependabot PR once bumped `react-dom` 18 → 19 while `react` stayed at 18. The
split compiled, installed, and served 200s, but the app never mounted — a blank
`#root` in production with no console error. `strict-peer-dependencies` in
`.npmrc` did not catch it, for two compounding reasons:

- With `autoInstallPeers` on, react-dom 19 resolves against the existing
  react 18 and is baked into the lockfile as "satisfied" — there is no _unmet_
  peer to flag.
- `--frozen-lockfile` (used in CI) replays the lockfile and never re-evaluates
  peers at all.

## Decision

Assert the **installed majors directly** rather than relying on peer
resolution. `scripts/check-react-pairing.mjs` resolves `react`, `react-dom`,
and their `@types/*` from the app and fails if their majors diverge; it runs in
the CI build job. `.npmrc` keeps `strict-peer-dependencies` on as
defence-in-depth for everyday (non-frozen) installs.

It sits in a layered defence:

- **Prevent** at the source — Dependabot now bumps the react family together,
  majors included (ADR 0001), so the split shouldn't be proposed.
- **Catch** the version split — this pairing gate.
- **Catch** any other blank-render cause — the deployed-preview smoke test
  asserts `#root` actually mounts, since a build can be green yet render blank.

## Consequences

- **+** The exact production incident class now fails CI deterministically,
  where peer-dependency settings could not.
- **+** Inspecting installed versions is robust to the lockfile and
  peer-resolution quirks that hid the original bug.
- **−** The check is react-specific; another ecosystem would need its own
  pairing assertion — cheap to add by the same pattern.
