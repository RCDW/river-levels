variable "location" {
  type    = string
  default = "uksouth" # UK South - nearest region
}

variable "name_prefix" {
  type        = string
  default     = "river-levels"
  description = "Prefix for resource names that need not be globally unique."
}

variable "resource_group_name" {
  type    = string
  default = "river-levels-rg"
}

# Storage account / workspace names must be GLOBALLY UNIQUE; no defaults so a
# real, checked value is supplied in terraform.tfvars rather than guessed.
variable "lake_account_name" {
  type        = string
  description = "ADLS Gen2 (data lake) storage account name. 3-24 chars, lowercase alphanumeric, globally unique."
}

variable "function_storage_account_name" {
  type        = string
  description = "Plain storage account backing the Functions runtime (AzureWebJobsStorage). Globally unique."
}

variable "function_app_name" {
  type        = string
  description = "Function App name (becomes <name>.azurewebsites.net). Globally unique."
}

variable "synapse_workspace_name" {
  type        = string
  description = "Synapse workspace name. Globally unique."
}

variable "synapse_sql_administrator_login" {
  type    = string
  default = "sqladminuser"
}

variable "synapse_sql_administrator_login_password" {
  type        = string
  sensitive   = true
  description = "Set via TF_VAR_synapse_sql_administrator_login_password at apply time; never commit it."
}

variable "github_repo" {
  type        = string
  description = "owner/repo, e.g. RCDW/river-levels - used for the OIDC federated credential subject."
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "tags" {
  type    = map(string)
  default = {}
}
