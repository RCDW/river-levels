variable "aws_region" {
  type    = string
  default = "eu-west-2" # London
}
variable "domain_name" {
  type        = string
  description = "Site domain served by CloudFront, e.g. live.reecewall.dev"
}
variable "cloudflare_zone_name" {
  type        = string
  description = "Cloudflare zone (apex) that owns the DNS, e.g. reecewall.dev. The site is a subdomain within it."
}
variable "subject_alternative_names" {
  type    = list(string)
  default = [] # single subdomain; no extra SANs
}
variable "github_repo" {
  type        = string
  description = "owner/repo, e.g. RCDW/river-levels"
}
variable "github_branch" {
  type    = string
  default = "main"
}
