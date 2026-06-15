# The data lake: ADLS Gen2 (hierarchical namespace ON). One lake feeds the
# Function (write), dbt/DuckDB + Synapse (read) and ADF. "Public access
# disabled" here means NO anonymous blob access - authenticated callers (managed
# identity / OIDC) still reach it over the public endpoint, which is what the
# Function, GitHub Actions and Synapse serverless all rely on.
resource "azurerm_storage_account" "lake" {
  name                            = var.lake_account_name
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  is_hns_enabled                  = true # ADLS Gen2
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false # no anonymous public blobs
  tags                            = local.tags
}

# Data-plane access is via managed identity / OIDC RBAC (see role assignments),
# not the account keys.
resource "azurerm_storage_data_lake_gen2_filesystem" "lake" {
  name               = "lake"
  storage_account_id = azurerm_storage_account.lake.id
}

# The Functions runtime needs its own (plain, non-HNS) storage account for
# AzureWebJobsStorage; the HNS lake is for data, not the runtime.
resource "azurerm_storage_account" "func" {
  name                            = var.function_storage_account_name
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = local.tags
}
