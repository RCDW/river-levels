# New repository checklist — from commit one

A distilled, reusable setup checklist for standing up a new repo with the
CI/CD + IaC posture this repo arrived at. Each item links to its reference
implementation here and, where it differs, a **→ data** note adapting it for an
IaC-heavy data project like `river-levels` (dbt / pipelines instead of a web
build).

Legend: **[universal]** applies anywhere · **[web]** specific to a frontend ·
**→ data** the data-project translation.

## 0. Repo hygiene first commit

- [ ] **[universal]** Add `.gitattributes` with `* text=auto eol=lf` **before**
      anything else. Without it, Windows `core.autocrlf` leaves the working tree
      CRLF while the repo stores LF, which produces phantom Prettier/format
      failures that don't reproduce on Linux CI. (This repo learned that the
      hard way: `.gitattributes` was added late, after the phantom failures kept
      surfacing — do it on commit one instead.)
- [ ] **[universal]** `.gitignore` excludes build output, `node_modules`, env
      files, and **all IaC state/secrets** (`*.tfstate*`, `*.tfvars`,
      `.terraform/`). Verify with `git check-ignore`.

## 1. Branch protection & flow

- [ ] **[universal]** Protect `main`: require PRs, require status checks to pass,
      block force-pushes and deletions.
- [ ] **[universal]** Squash-merge only, so the PR title is the commit — written
      as a Conventional Commit (subject ≤50, body ≤72).
- [ ] **[universal]** One logical change per PR; diagnose before building; prove
      any gate red→green locally before opening.

## 2. Secrets & supply chain

- [ ] **[universal]** No stored cloud keys — deploy via **GitHub OIDC** into a
      least-privilege role (see [ADR 0003](adr/0003-s3-cloudfront-over-vercel.md)
      and `infra/*_oidc.tf`). Separate roles per environment; a preview role must
      not be able to touch prod.
- [ ] **[universal]** Enable **secret scanning + push protection** (repo
      Settings → Code security). Free on public repos; mechanically blocks
      committing a recognised token.
- [ ] **[universal]** **Pin every GitHub Action to a commit SHA** with a `# vN`
      comment; let Dependabot bump the SHA. See `.github/workflows/*`.
- [ ] **[universal]** Explicit minimal **`permissions:`** on every workflow
      (default `contents: read`; grant `id-token`/`pull-requests` per job that
      needs them).

## 3. Lint / format / hooks

- [ ] **[universal]** A formatter + linter with a **`format:check`** + **lint**
      CI gate. Here: Prettier + ESLint (flat config).
      → **data**: `sqlfluff` for SQL, `ruff`/`black` for Python, `dbt parse`.
- [ ] **[universal]** Pre-commit hook (husky + lint-staged) that formats/lints
      staged files, so CI rarely fails on style.

## 4. The CI gate that proves the artifact _works_

The core lesson of this repo: **"compiles and serves 200s" is not "works".** A
build can be green and still render a blank page.

- [ ] **[universal]** Build/typecheck gate.
- [ ] **[web]** **Smoke test**: serve the production build and load it in a real
      browser, asserting it actually mounts and logs no errors (see
      [ADR 0006](adr/0006-peer-dependency-gate.md) and the Playwright smoke
      test). Run it against the deployed preview too.
      → **data**: make **`dbt build` + `dbt test`** the gate — assert the
      pipeline produced a **queryable, tested** artifact (models materialised,
      tests/freshness passing), not merely that the SQL compiled. This is the
      exact same idea as the smoke test, in the data world.

## 5. Dependency hygiene

- [ ] **[universal]** Dependabot for the package ecosystem **and**
      `github-actions`, weekly, grouped. **Group tightly-coupled families so
      their majors bump together** — an uncoordinated `react-dom` major once
      blanked prod (see [ADR 0001](adr/0001-dependency-automation.md)).
      → **data**: group `dbt-core` with its adapter (`dbt-snowflake`, etc.) so
      they never split across a major.
- [ ] **[universal]** Know the **strict-peer caveat**: with `autoInstallPeers`
      on, a major split resolves against the old version and is baked into the
      lockfile as "satisfied", and `--frozen-lockfile` never re-checks peers — so
      **assert installed versions directly** rather than trusting peer
      resolution ([ADR 0006](adr/0006-peer-dependency-gate.md)).

## 6. Infrastructure as code + its gates

- [ ] **[universal]** Terraform with **remote state** (S3 + native locking); no
      secrets in state or tfvars (gitignored). See
      [ADR 0004](adr/0004-terraform-over-cdk.md).
- [ ] **[universal]** CI gate scoped to `infra/**`: **`terraform fmt -check` +
      `tflint` + a misconfig scanner** (Trivy). Baseline accepted findings in a
      documented `.trivyignore` so the gate stays green on accepted risk but
      fails on anything new. See `.github/workflows/infra.yml`.

## 7. Deploy pipeline

- [ ] **[universal]** Deploy on push to `main` (paths-filtered) via the OIDC
      role.
- [ ] **[universal]** **Never cancel an in-flight deploy**
      (`cancel-in-progress: false`) — a non-atomic deploy cancelled mid-flight
      can corrupt prod or leave it behind `main`. Keep a `workflow_dispatch`
      "deploy current main" safety net. See `deploy.yml`.
      → **data**: even more important — a cancelled mid-run load leaves
      partial/duplicate data. Prefer idempotent, transactional loads.
- [ ] **[web]** Cache strategy: immutable hashed assets, never-cached entry
      point, invalidate + **wait** for completion before downstream checks.

## 8. Per-PR ephemeral environments

- [ ] **[universal]** Per-PR preview, **isolated** and **least-privilege**, torn
      down on PR close; fork-safe (no secrets to forks). See
      [ADR 0005](adr/0005-preview-environment-isolation.md).
      → **data**: build into a **per-PR scoped schema/dataset** (e.g.
      `dbt build --target pr_<n>`), validate it, drop it on close — the data
      analog of subdomain isolation.
- [ ] **[universal]** Validate the deployed preview, not just the local build.
- [ ] **[universal/informational]** Quality signal that starts **informational**
      and only becomes blocking once stable (Lighthouse here;
      → **data**: dbt test pass-rate, freshness, row-count anomaly checks).

## 9. Decision records

- [ ] **[universal]** `docs/adr/` with a README + template; record every
      hard-to-reverse decision, honestly (real reasons, not impressive ones).
      ADRs are immutable once accepted — supersede, don't rewrite.

## 10. Reusable assets — what to carry from this repo

Standing up a new repo (e.g. `river-levels`) shouldn't restart from zero. Carry
the posture across deliberately: copy what's truly generic verbatim, adapt what
encodes a web-specific choice, and let the new repo write its own decisions.

- [ ] **Copy verbatim (universal):**
  - `.gitattributes` (item 0 — first commit).
  - `docs/adr/README.md` + `docs/adr/template.md` (the ADR scaffolding and
    conventions).
  - This checklist itself, as the new repo's setup runbook.
  - The never-cancel deploy pattern (`concurrency: cancel-in-progress: false` +
    a `workflow_dispatch` safety net) from `deploy.yml`.
  - SHA-pinned actions with `# vN` comments and explicit minimal
    `permissions:` on every workflow.
  - The OSV gate shape (`security-scan.yml` + a dated, documented
    `osv-scanner.toml`).
  - The infra static-analysis gate (`fmt -check` + `tflint` + Trivy) with
    documented `.trivyignore` / `.tflint.hcl` baselines. **Note:** the `infra`
    workflow is static analysis only — `terraform apply` is run by a human, not
    in CI.

- [ ] **Adapt (re-author for the new repo):**
  - The OIDC deploy-role pattern — per-environment, least-privilege; a preview
    role must never reach prod.
  - The Dependabot config — swap ecosystems (e.g. `pip` for the Python deps,
    keep `github-actions`).
  - Project-level working notes / architecture overview, as templates.

- [ ] **Which ADRs port:** `0001` (dependency automation — group `dbt-core` with
      its adapter so majors bump together), `0003` (static hosting — a dashboard's
      `web/` is static too), `0004` (Terraform + remote state), `0005` (preview
      environments → a per-PR scoped schema/dataset, the data analog of subdomain
      isolation). **Web-only, don't port:** `0002` (Vite over Next) and `0006` (the
      react/react-dom peer gate) — though the lesson behind `0006` (assert installed
      versions, don't trust peer resolution) becomes its **own** new ADR in the data
      repo (e.g. asserting `dbt-core`/adapter versions).

- [ ] **The new repo writes its own ADRs** for its real decisions — e.g.
      bronze append-only / medallion layering, the dbt + DuckDB / Azure hybrid, one
      ingest module with two runners, last-known-good publish. Record the reasons
      that actually drove them, same as here.

---

**Reference implementation:** this repo (`reecewall.dev`). The ADRs in
`docs/adr/` explain the _why_ behind several of these; the workflows in
`.github/workflows/` and `infra/` are the _how_.
