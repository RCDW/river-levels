data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.domain_name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Edge function: map clean, extensionless URLs to the prerendered nested
# index.html files (SSG output). S3 OAC origins do no directory-index
# resolution, so this owns that mapping. See router.js. Backward-compatible
# with a single-index.html SPA build (unknown keys fall through to the 403
# fallback below), so it is safe to apply before the prerendered build ships.
resource "aws_cloudfront_function" "router" {
  name    = "${replace(var.domain_name, ".", "-")}-router"
  runtime = "cloudfront-js-2.0"
  comment = "Map clean URLs to prerendered /<route>/index.html"
  publish = true
  code    = file("${path.module}/router.js")
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  default_root_object = "index.html"
  aliases             = concat([var.domain_name], var.subject_alternative_names)
  price_class         = "PriceClass_100" # NA + EU; cheapest

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "s3-site"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id           = "s3-site"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.router.arn
    }
  }

  # Unknown keys: private S3 returns 403 -> serve the app shell so the client
  # router can render the route (known routes resolve to real files via the
  # viewer-request function above; this is the fallback for everything else).
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.site.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

resource "aws_cloudfront_response_headers_policy" "security" {
  name = "${replace(var.domain_name, ".", "-")}-security-headers"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = true
      preload                    = false
      override                   = true
    }
    content_type_options { override = true }
    frame_options {
      frame_option = "SAMEORIGIN"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }
}