data "cloudflare_zone" "site" {
  name = var.domain_name
}

# Apex → CloudFront
resource "cloudflare_record" "apex" {
  zone_id = data.cloudflare_zone.site.id
  name    = var.domain_name
  type    = "CNAME"
  content = aws_cloudfront_distribution.site.domain_name
  proxied = false # DNS-only; CloudFront is the edge
}

resource "cloudflare_record" "www" {
  zone_id = data.cloudflare_zone.site.id
  name    = "www"
  type    = "CNAME"
  content = aws_cloudfront_distribution.site.domain_name
  proxied = false
}