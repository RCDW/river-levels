# W6 - Azure hybrid: provision, parallel-run, cutover, rollback

**Goal:** move *ingest* from GitHub Actions to an Azure Function + ADLS Gen2,
expose the lake in Synapse serverless, and land an ADF evidence pipeline -
**additively**, without breaking `live.reecewall.dev` and without a monthly
bill. Transform + serve stay dbt + DuckDB. The migration runs in parallel, then
cuts over with a one-switch rollback.

> The spine: "Azure where it earns its place (durable cloud landing,
> file-arrival monitoring, serverless query), the free modern stack where it's
> the better fit. The same gold model is queryable three ways."

The dashboard (`web/`), the published artifacts, the `data` branch -> CDN flow,
and the AWS hosting/deploy are **untouched**. Only the source of bronze (now
ADLS) and the ingest runner (now the Function) move.

## One lake, four consumers

```
EA API -> Azure Function (timer, Consumption) -> ADLS Gen2  lake/bronze/**.parquet
                                                    |  ^          ^
   DuckDB (build, azure ext) reads ----------------+  |          |
   Synapse serverless external views read -----------+          |
   ADF copy pipeline (on-demand evidence) writes lake/evidence/-+
```

---

## What Claude built vs what you run

Everything in the repo is authored; **every cloud action is yours** - nothing
that creates resources, deploys, or incurs cost was run by Claude.

| Area | In the repo (done) | You run |
| --- | --- | --- |
| Terraform | `infra/azure/*.tf` (validated, fmt clean) | `terraform init/plan/apply` |
| Function | `azure_function/function_app.py` (v2), `host.json`, `requirements.txt` | `func azure functionapp publish`, set app settings |
| dbt | `azure` target in `transform/profiles.yml` | `dbt --target azure` against the lake |
| Synapse | `synapse/external_views.sql` | create workspace, run the SQL |
| ADF | `adf/pipeline_copy_ea_to_bronze.json` | import + wire linked services, run on demand |
| Workflow | `.github/workflows/pipeline_azure.yml` | set repo secrets/vars, enable, cut over |

---

## 0. Subscription prerequisites (new accounts)

A brand-new subscription ships with limits that block the compute plane even
though the storage plane provisions fine. Two were hit on first apply:

- **App Service compute quota of 0.** The Consumption Function plan needs at
  least one VM of quota; a fresh subscription often has `Total VMs: 0` and the
  plan fails with a 401 quota error. Request it once: Portal -> your
  **Subscription -> Settings -> Usage + quotas** -> filter to App Service / your
  region -> request a limit of >= 1 (free, usually granted quickly). Changing
  the SKU does not avoid it.
- **Region must accept new SQL servers.** Synapse provisions a SQL server under
  the hood; some subscriptions cannot create new SQL servers in `uksouth`
  (`SqlServerRegionDoesNotAllowProvisioning`). The default region is therefore
  **`ukwest`** (`var.location`); pick another region (or raise a support
  request) if ukwest is also restricted for your subscription.

## 1. Provision (Terraform - human-run)

`apply` is human-run, never CI (same rule as the AWS infra).

```bash
cd infra/azure
export ARM_SUBSCRIPTION_ID=<sub-id>
export TF_VAR_synapse_sql_administrator_login_password='<strong-password>'
cp terraform.tfvars.example terraform.tfvars   # edit the globally-unique names
terraform init
terraform plan
terraform apply
```

This creates: resource group (UK West, see section 0); the ADLS Gen2 lake (HNS on, no
anonymous access); the Functions runtime storage account; the Consumption
Function App with a system-assigned identity (Storage Blob Data Contributor on
the lake); the GitHub Actions user-assigned identity + OIDC federated credential
(Contributor on the lake); the Synapse workspace (serverless, Reader on the
lake).

Note the outputs - you need them in steps 2, 4 and 6:
`lake_account_name`, `function_app_name`, `github_actions_client_id`,
`tenant_id`, `subscription_id`, `synapse_workspace_name`,
`synapse_serverless_endpoint`.

---

## 2. Deploy the ingest Function (v2)

The deployment package must include the repo's `ingest/` package (so
`from ingest import ea_client` resolves) and `config/stations.yml` - vendor them
into the function folder, or publish from a root that has both on the path. The
function also reads `STATIONS_CONFIG` if you prefer an explicit path.

App settings (Terraform already sets `LAKE_ACCOUNT_URL` and `LAKE_CONTAINER`;
confirm them):

- `LAKE_ACCOUNT_URL = https://<lake_account_name>.blob.core.windows.net`
- `LAKE_CONTAINER  = lake`

Deploy with `func azure functionapp publish <function_app_name>` (or VS Code).

**Verify file landing:** after the first timer fire, confirm
`lake/bronze/dt=YYYY-MM-DD/batch_*.parquet` appears and `bronze/_latest.json`
updates - that heartbeat is the "files land on time" monitoring story; wire a
cheap alert later if `_latest.json` goes stale.

---

## 3. Repoint dbt at the lake (verify)

The `azure` target is already in `transform/profiles.yml`. To test it yourself:

```bash
az login                                        # credential_chain picks up the CLI
export LAKE_ACCOUNT_NAME=<lake_account_name>
export BRONZE_GLOB='abfss://lake/bronze/**/*.parquet'
cd transform
dbt deps
dbt run  --profiles-dir . --target azure
dbt test --profiles-dir . --target azure        # must be green against the lake
```

Same models, now reading bronze from ADLS; the layers stay individually
queryable, so Feature C still works. (Linux gotcha: if the azure extension hits
a curl CA error, install `ca-certificates` / set the transport option.)

---

## 4. Synapse serverless - the showcase surface

- In the workspace, add a firewall rule for your client IP (Studio ->
  Networking) - left out of Terraform so we don't commit an allow-all rule.
- In `synapse/external_views.sql`, replace `REPLACE_ACCOUNT` (3 places) with
  `lake_account_name`.
- Run it in the Built-in pool: it sets the monthly data-processed cap, then
  creates the `river_lake` DB with `gold.station_latest`, `gold.series`,
  `gold.silver_readings` over `lake/publish/parquet/*.parquet`.
- The published Parquet is landed by the workflow (step 6). Verify the figures
  match the dashboard:
  ```sql
  SELECT station_label, latest_value, change_24h, above_threshold
  FROM gold.station_latest ORDER BY above_threshold DESC;
  ```

---

## 5. ADF evidence pipeline (on-demand, ~GBP 0)

Import `adf/pipeline_copy_ea_to_bronze.json`, wire the two linked services and
two datasets noted in the file (it lands at `lake/evidence/adf/`, deliberately
outside the dbt bronze glob). **Do not schedule it** - run manually so there is
no standing integration-runtime cost. It proves ADF without paying to run it.

---

## 6. Switch the scheduler & parallel-run

Set, from the Terraform outputs:

- Repo **secrets:** `AZURE_CLIENT_ID` (= `github_actions_client_id`),
  `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`.
- Repo **variable:** `LAKE_ACCOUNT_NAME`.

`.github/workflows/pipeline_azure.yml` then runs `dbt --target azure` ->
publish -> uploads the published Parquet to `lake/publish/` -> pushes `web/data`
to the `data` branch.

**Parallel run for a few days:** keep the W3 `pipeline.yml` on while the
Function and the hybrid workflow run alongside. They use distinct concurrency
groups, so they don't cancel each other; both force-push `web/data` to the
`data` branch, so during the window the latest run wins - confirm the site stays
correct and the two produce consistent artifacts (same `gold.json` figures,
same row counts in `run_meta.json`).

**Cutover (one switch):** disable `.github/workflows/pipeline.yml` (rename it
`*.yml.disabled`, or in the GitHub UI: Actions -> river-pipeline -> Disable
workflow). The Function now owns ingest; the hybrid workflow owns transform/serve.

---

## 7. Rollback (one switch)

Re-enable `pipeline.yml` (the full free path), and disable the hybrid workflow +
the Function timer. Because ingest is the *same* `ea_client` module, there is
nothing to rewrite - it is purely which runner is on. The trace key
(`reading_id`) is minted in that shared core, so data produced by either runner
is identical.

---

## Cost (verified, per component)

| Component | Rate | Usage | Cost |
| --- | --- | --- | --- |
| Functions (Consumption) | free: 1M exec + 400k GB-s/mo | ~240 runs/mo, seconds each | GBP 0 |
| Function's runtime storage | standard | tiny | pennies |
| ADLS Gen2 (hot) | ~GBP 0.018/GB/mo | few GB rolling | pennies |
| Synapse serverless | $5/TB, 10 MB min, free DDL/cached | MB-scale -> 10 MB floor | ~GBP 0.00005/query |
| ADF | per-1,000 activity runs | on-demand only | ~GBP 0 |
| App Insights (Log Analytics) | free: 5 GB ingest/mo | tiny telemetry, 30-day retention | GBP 0 |
| Egress -> Actions | first 100 GB/mo free | <1 GB | GBP 0 |

**Total ~GBP 0.20-0.50/month**, stated honestly; the Synapse data-processed cap
guards the only thing that could surprise the bill.
