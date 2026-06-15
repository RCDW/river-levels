output "lake_account_name" {
  value       = azurerm_storage_account.lake.name
  description = "Set as the LAKE_ACCOUNT_NAME repo variable (dbt azure target)."
}

output "lake_account_url" {
  value = "https://${azurerm_storage_account.lake.name}.blob.core.windows.net"
}

output "function_app_name" {
  value = azurerm_linux_function_app.ingest.name
}

output "github_actions_client_id" {
  value       = azurerm_user_assigned_identity.github_actions.client_id
  description = "Set as the AZURE_CLIENT_ID repo secret."
}

output "tenant_id" {
  value       = data.azurerm_client_config.current.tenant_id
  description = "Set as the AZURE_TENANT_ID repo secret."
}

output "subscription_id" {
  value       = data.azurerm_client_config.current.subscription_id
  description = "Set as the AZURE_SUBSCRIPTION_ID repo secret."
}

output "synapse_workspace_name" {
  value = azurerm_synapse_workspace.this.name
}

output "synapse_serverless_endpoint" {
  value = azurerm_synapse_workspace.this.connectivity_endpoints["sqlOnDemand"]
}
