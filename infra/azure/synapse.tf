# Synapse workspace - the serverless built-in pool only (no dedicated SQL pool,
# so no idle cost). It needs an ADLS Gen2 filesystem as its default; we give it
# a dedicated 'synapse' filesystem, kept separate from the data lake filesystem.
resource "azurerm_storage_data_lake_gen2_filesystem" "synapse" {
  name               = "synapse"
  storage_account_id = azurerm_storage_account.lake.id
}

resource "azurerm_synapse_workspace" "this" {
  name                                 = var.synapse_workspace_name
  resource_group_name                  = azurerm_resource_group.this.name
  location                             = azurerm_resource_group.this.location
  storage_data_lake_gen2_filesystem_id = azurerm_storage_data_lake_gen2_filesystem.synapse.id
  sql_administrator_login              = var.synapse_sql_administrator_login
  sql_administrator_login_password     = var.synapse_sql_administrator_login_password

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

# The workspace identity may READ the lake (the published gold/silver parquet
# the external views in synapse/external_views.sql query). Read-only - Synapse
# never writes the lake.
resource "azurerm_role_assignment" "synapse_lake_reader" {
  scope                = azurerm_storage_account.lake.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_synapse_workspace.this.identity[0].principal_id
}

# NOTE: to query from Synapse Studio you must add a workspace firewall rule for
# your client IP (Studio -> Networking, or an azurerm_synapse_firewall_rule).
# Left out of Terraform deliberately - committing an allow-all rule would widen
# access; scope it to your IP at apply time. See docs/w6-cutover-runbook.md.
