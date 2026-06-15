# GitHub Actions authenticates to Azure via OIDC federated credentials on a
# user-assigned managed identity - no client secret stored. Mirrors the AWS
# OIDC deploy role. The hybrid workflow uses this identity to read bronze from
# the lake and write the published parquet back to lake/publish/.
resource "azurerm_user_assigned_identity" "github_actions" {
  name                = "${var.name_prefix}-gha"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "github_actions" {
  name                = "github-actions-${var.github_branch}"
  resource_group_name = azurerm_resource_group.this.name
  parent_id           = azurerm_user_assigned_identity.github_actions.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${var.github_repo}:ref:refs/heads/${var.github_branch}"
}

# Contributor (not just Reader) because the workflow also writes the published
# gold/silver parquet to lake/publish/ for Synapse. It never writes bronze.
resource "azurerm_role_assignment" "github_actions_lake_contributor" {
  scope                = azurerm_storage_account.lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.github_actions.principal_id
}
