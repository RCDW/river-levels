# tflint configuration for infra/.
#
# Uses the bundled `terraform` language ruleset (recommended preset) only, no
# cloud provider plugins, so the CI lint needs no network calls or AWS
# credentials. Security/misconfiguration scanning is handled separately by
# Trivy; tflint's job here is terraform-level hygiene: deprecated syntax,
# unused declarations, missing variable/output documentation, naming.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
