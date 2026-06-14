data "cloudflare_zone" "site" {
  name = var.cloudflare_zone_name
}

# live.reecewall.dev → CloudFront (DNS-only; CloudFront is the edge).
# The site is a subdomain within the apex zone; name is the full record name.
resource "cloudflare_record" "site" {
  zone_id = data.cloudflare_zone.site.id
  name    = var.domain_name
  type    = "CNAME"
  content = aws_cloudfront_distribution.site.domain_name
  proxied = false
}
