# Wildcard cert covering pr-N.preview.reecewall.dev. Separate from the prod
# cert so the preview distribution is fully independent. us-east-1 because
# CloudFront only reads ACM certs from that region.
resource "aws_acm_certificate" "preview" {
  provider          = aws.us_east_1
  domain_name       = "*.preview.${var.domain_name}"
  validation_method = "DNS"
  lifecycle { create_before_destroy = true }
}

# Same manual validation flow as the prod cert (see acm.tf): pull the CNAME
# and add it as a DNS-only record in Cloudflare by hand:
#   aws acm describe-certificate --region us-east-1 \
#     --certificate-arn <preview_cert_arn> \
#     --query "Certificate.DomainValidationOptions[].ResourceRecord"
resource "aws_acm_certificate_validation" "preview" {
  provider        = aws.us_east_1
  certificate_arn = aws_acm_certificate.preview.arn
  timeouts {
    create = "15m"
  }
}
