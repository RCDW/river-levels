# Security

This is a public portfolio project serving **already-public** Environment Agency
open data. The threat model reflects that: confidentiality of the *data* is not
a concern; the concerns are secret hygiene, the CI/CD trust boundary, cost
abuse, and standard web hardening.

## Posture

| Area | Control |
|---|---|
| Secrets | None in code or repo. GitHub Actions authenticates to AWS and Azure with **OIDC federated credentials**; the Azure Function uses a **managed identity**. `.gitignore` excludes `*.tfstate*`, `*.tfvars`, `.terraform/`, `.env`. |
| CI/CD trust boundary | The scheduled **pipeline** workflow (`pipeline_azure.yml`, write + cloud auth) runs only on `schedule` and `workflow_dispatch`, never on fork PRs. The **CI** workflow runs on `pull_request` with `permissions: contents: read` and **no secrets**. |
| Least-privilege publish | The pipeline self-publishes fresh data with a **dedicated** OIDC role (`<domain>-gha-data-publish`, ADR 0018): `s3:PutObject`/`s3:DeleteObject` confined to the `data/*` prefix and a `/data/*` CloudFront invalidation only. It cannot touch the rest of the site; `deploy.yml` keeps its own separate role for code/asset deploys. |
| Supply chain | DuckDB-WASM is pinned to a fixed version (`@duckdb/duckdb-wasm@1.29.0`, not `@latest`); third-party Actions are pinned to commit SHA; Dependabot covers pip + Actions (dbt-core grouped with dbt-duckdb); an OSV-Scanner gate (`security-scan.yml` + `osv-scanner.toml`) runs on PRs and weekly. |
| Cloud storage | ADLS Gen2 has **public anonymous access disabled**; the browser reads only the CDN-published copy. Lake access is via managed identity / RBAC, not account keys. |
| Ingress | The Azure Function is **timer-triggered only**, with no public HTTP endpoint to abuse. |
| Cost / financial DoS | Synapse serverless carries a **data-processed budget cap**; the endpoint is restricted to Entra ID auth. AWS spend is budget-capped and the data publish is a narrow, cheap sync. |
| Browser SQL (click-to-trace) | Queries run **client-side** against read-only public Parquet. The three layer queries use **parameterised `?` placeholders**; as defence in depth, `reading_id` is additionally regex-restricted to md5 hex before it ever reaches SQL. |
| DOM rendering | Trace and metric values are inserted via `createElement` + `textContent`, never `innerHTML` of data values, so markup in an upstream field cannot execute. |

## Reporting

Found something? Email rcdwall@gmail.com. This is a personal project with no
SLA, but security reports are welcome and credited.
