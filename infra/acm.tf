resource "aws_acm_certificate" "site" {
  provider                  = aws.us_east_1
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"
  lifecycle { create_before_destroy = true }
}

# DNS validation records are created MANUALLY in Cloudflare (DNS-only / grey cloud).
# Pull the required CNAME(s) with:
#   aws acm describe-certificate --region us-east-1 \
#     --certificate-arn <arn> \
#     --query "Certificate.DomainValidationOptions[].ResourceRecord"
# then add each Name/Value as a DNS-only CNAME in the Cloudflare dashboard.

resource "aws_acm_certificate_validation" "site" {
  provider        = aws.us_east_1
  certificate_arn = aws_acm_certificate.site.arn
  # No validation_record_fqdns: we are not creating the records in Terraform.
  # This resource simply waits for the cert to reach ISSUED once Cloudflare
  # is serving the validation CNAME(s).
  timeouts {
    create = "15m"
  }
}
