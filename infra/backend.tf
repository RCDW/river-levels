terraform {
  backend "s3" {
    bucket       = "reecewall-dev-tfstate" # shared state bucket; this repo owns its own key
    key          = "river-levels/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true # native S3 locking, no DynamoDB needed (TF 1.10+)
  }
}