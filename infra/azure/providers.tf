terraform {
  required_version = ">= 1.10"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
}

provider "azurerm" {
  features {}
  # subscription_id is read from ARM_SUBSCRIPTION_ID at apply time, so no
  # subscription id is committed to the repo.
}

data "azurerm_client_config" "current" {}
