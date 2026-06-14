# ============================================================================
# Preview environment - isolated bucket + distribution serving every open PR
# under pr-N.preview.reecewall.dev. Shares nothing writable with prod.
# ============================================================================

# --- Bucket: private, same OAC pattern as prod. One bucket, one prefix per PR.
resource "aws_s3_bucket" "preview" {
  bucket = "preview.${var.domain_name}"
}

resource "aws_s3_bucket_public_access_block" "preview" {
  bucket                  = aws_s3_bucket.preview.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "preview" {
  name                              = "${var.domain_name}-preview-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# --- Edge function: host -> prefix mapping + per-PR SPA fallback.
resource "aws_cloudfront_function" "preview_router" {
  name    = "${replace(var.domain_name, ".", "-")}-preview-router"
  runtime = "cloudfront-js-2.0"
  comment = "Map pr-N.preview host to /pr-N/* keys; SPA fallback to per-PR index.html"
  publish = true
  code    = file("${path.module}/preview_router.js")
}

# --- Distribution: mirrors prod settings, adds the router function. No
#     custom_error_response here the function owns SPA fallback per PR.
resource "aws_cloudfront_distribution" "preview" {
  enabled         = true
  aliases         = ["*.preview.${var.domain_name}"]
  price_class     = "PriceClass_100"
  is_ipv6_enabled = true

  origin {
    domain_name              = aws_s3_bucket.preview.bucket_regional_domain_name
    origin_id                = "s3-preview"
    origin_access_control_id = aws_cloudfront_origin_access_control.preview.id
  }

  default_cache_behavior {
    target_origin_id           = "s3-preview"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.preview_router.arn
    }
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.preview.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# --- Bucket policy: only the preview distribution may read it.
resource "aws_s3_bucket_policy" "preview" {
  bucket = aws_s3_bucket.preview.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowPreviewCloudFrontOAC"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.preview.arn}/*"
      Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.preview.arn } }
    }]
  })
}

# --- DNS: one wildcard record covers every PR subdomain. Reuses the zone
#     looked up in cloudflare.tf.
resource "cloudflare_record" "preview_wildcard" {
  zone_id = data.cloudflare_zone.site.id
  name    = "*.preview"
  type    = "CNAME"
  content = aws_cloudfront_distribution.preview.domain_name
  proxied = false # DNS-only; CloudFront is the edge, same as prod
}

# --- Outputs the preview workflow consumes.
output "preview_bucket" { value = aws_s3_bucket.preview.bucket }
output "preview_distribution_id" { value = aws_cloudfront_distribution.preview.id }
output "preview_deploy_role_arn" { value = aws_iam_role.preview_deploy.arn }
