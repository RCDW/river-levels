# infra/azure - Azure side of the W6 hybrid

Terraform (azurerm) for the W6 Azure resources, kept separate from the AWS
infra in `../` with its own state key (`river-levels/azure.tfstate` in the
shared bucket). The AWS static hosting/deploy of `live.reecewall.dev` is
untouched by anything here.

**What it provisions**

- Resource group (UK South).
- ADLS Gen2 storage account (`is_hns_enabled`), the data **lake**, with no
  anonymous public access. Data-plane access is RBAC via managed identity / OIDC.
- A plain storage account for the Functions runtime.
- Function App on the **Consumption** plan, Python 3.12, system-assigned
  identity, granted **Storage Blob Data Contributor** on the lake.
- A user-assigned identity for **GitHub Actions** with an OIDC **federated
  credential** (no stored secret), granted **Storage Blob Data Contributor**
  (reads bronze, writes `lake/publish/`).
- Synapse workspace (serverless built-in pool only - no idle cost), its identity
  granted **Storage Blob Data Reader** on the lake.

**Apply is human-run, never CI** (same rule as the AWS infra). The CI `infra`
workflow is static analysis only.

```bash
cd infra/azure
export ARM_SUBSCRIPTION_ID=<sub>
export TF_VAR_synapse_sql_administrator_login_password=<pick-a-strong-password>
cp terraform.tfvars.example terraform.tfvars   # then edit the unique names
terraform init
terraform plan
terraform apply        # human only
```

After apply, wire the outputs into GitHub (see `docs/w6-cutover-runbook.md`):
`github_actions_client_id` -> `AZURE_CLIENT_ID`, `tenant_id` -> `AZURE_TENANT_ID`,
`subscription_id` -> `AZURE_SUBSCRIPTION_ID` (secrets), `lake_account_name` ->
`LAKE_ACCOUNT_NAME` (variable).

To query from Synapse Studio, add a workspace firewall rule for your client IP
(left out of Terraform so we don't commit an allow-all rule).
