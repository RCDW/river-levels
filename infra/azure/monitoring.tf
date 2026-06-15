# Application Insights for the Function - invocation logs (the file-arrival
# heartbeat story) and the "worker failed to index" diagnostics. Declaring it
# here replaces the manual portal setup, which was lost whenever the Function
# App was recreated. Workspace-based (classic App Insights is retired), so a
# Log Analytics workspace backs it.
#
# Cost: telemetry is tiny here (~240 short runs/month), well inside the free
# monthly ingestion grant; retention is trimmed to 30 days to keep it there.
resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.name_prefix}-law"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_application_insights" "this" {
  name                = "${var.name_prefix}-ai"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  workspace_id        = azurerm_log_analytics_workspace.this.id
  application_type    = "web"
  tags                = local.tags
}
