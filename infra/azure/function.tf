# Consumption plan (Y1): timer executions sit inside the free monthly grant
# (1M executions + 400k GB-s), so ingest costs ~GBP 0.
resource "azurerm_service_plan" "func" {
  name                = "${var.name_prefix}-func-plan"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  os_type             = "Linux"
  sku_name            = "Y1"
  tags                = local.tags
}

resource "azurerm_linux_function_app" "ingest" {
  name                       = var.function_app_name
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  service_plan_id            = azurerm_service_plan.func.id
  storage_account_name       = azurerm_storage_account.func.name
  storage_account_access_key = azurerm_storage_account.func.primary_access_key

  # Redirect HTTP to HTTPS. The Function is timer-triggered (no public ingress),
  # but this is free hardening and keeps the control plane TLS-only.
  https_only = true

  # System-assigned identity - the Function authenticates to the lake with this,
  # no connection string (see the role assignment below).
  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      python_version = "3.12"
    }

    # Wire App Insights via the native argument (host.json already enables the
    # logger). azurerm manages the linked app settings + hidden-link tag, so this
    # cleanly replaces the manual portal wiring without app_settings churn.
    application_insights_connection_string = azurerm_application_insights.this.connection_string

    # Allow the Azure portal origin so the Code + Test / Run button works without
    # a manual CORS entry. Only the portal test UI needs this; the scheduled timer
    # does not, and there are no HTTP-triggered functions here. The portal sets
    # support_credentials=true when you add the origin by hand - match it so apply
    # does not flip it off and break Test/Run.
    cors {
      allowed_origins     = ["https://portal.azure.com"]
      support_credentials = true
    }
  }

  app_settings = {
    # Consumed by azure_function/function_app.py (DefaultAzureCredential).
    LAKE_ACCOUNT_URL = "https://${azurerm_storage_account.lake.name}.blob.core.windows.net"
    LAKE_CONTAINER   = azurerm_storage_data_lake_gen2_filesystem.lake.name
    # Required for the Python v2 (decorator) programming model.
    AzureWebJobsFeatureFlags = "EnableWorkerIndexing"
  }

  tags = local.tags
}

# The Function's identity may WRITE bronze + the heartbeat to the lake.
resource "azurerm_role_assignment" "func_lake_contributor" {
  scope                = azurerm_storage_account.lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.ingest.identity[0].principal_id
}
