# 16. Azure IaC: azurerm with separate Terraform state

- **Status:** Accepted
- **Date:** 2026-06-15

## Context

W6 adds real Azure resources (lake, Function, identities, Synapse). They could
be clicked together in the portal, but the repo already treats infrastructure as
code (ADR 0004, Terraform for AWS) and the commit history is itself the product.
The question is whether to Terraform the Azure side too, and if so how to keep it
from entangling the live AWS state.

## Decision

Terraform the Azure side with the **azurerm** provider in `infra/azure/`, as a
**separate root module with its own state** (`river-levels/azure.tfstate` in the
same shared S3 bucket, native S3 locking). It mirrors the AWS infra conventions
(per-concern files, why-comments) and the same operating rule: **`apply` is
human-run, never CI** - the `infra` workflow stays static analysis only.

Auth is passwordless throughout: the Function and Synapse use system-assigned
managed identities; GitHub Actions uses a user-assigned identity with an OIDC
**federated credential** (`azurerm_federated_identity_credential`), so no client
secret is created or stored. The only sensitive input, the Synapse SQL admin
password, comes from `TF_VAR_*` at apply and is never committed.

Portal/CLI provisioning was rejected: it leaves no reviewable artifact and is
not reproducible. A shared state file with the AWS infra was rejected: separate
blast radius keeps an Azure change from touching live DNS/CDN state.

## Consequences

- **+** The Azure estate is reproducible, reviewable, and consistent with the
  AWS infra; a stronger portfolio artifact.
- **+** Separate state isolates failure; passwordless auth means no secrets in
  the repo.
- **-** Two Terraform roots to `init`/`apply` and keep formatted.
- **-** azurerm provider/version drift to track (Dependabot does not cover
  Terraform providers here; the lockfile is committed and bumped by hand).
