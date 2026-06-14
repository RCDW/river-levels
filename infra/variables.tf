variable "aws_region" {
  type    = string
  default = "eu-west-2" # London
}
variable "domain_name" {
  type        = string
  description = "Apex domain, e.g. reecewall.dev"
}
variable "subject_alternative_names" {
  type    = list(string)
  default = [] # e.g. ["www.reecewall.dev"]
}
variable "github_repo" {
  type        = string
  description = "owner/repo, e.g. RCDW/reecewall.dev"
}
variable "github_branch" {
  type    = string
  default = "main"
}
