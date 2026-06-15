locals {
  tags = merge({
    project = "river-levels"
    managed = "terraform"
    week    = "W6"
  }, var.tags)
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.tags
}
