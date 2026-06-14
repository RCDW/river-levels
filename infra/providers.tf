terraform {
  required_version = ">= 1.10"
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.60" }
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 4.0" }
  }
}

provider "aws" {
  region = var.aws_region
}

# CloudFront requires its ACM certificate in us-east-1, regardless of site region.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "cloudflare" {} # token from CLOUDFLARE_API_TOKEN env var