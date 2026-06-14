output "bucket_name" { value = aws_s3_bucket.site.bucket }
output "distribution_id" { value = aws_cloudfront_distribution.site.id }
output "cloudfront_domain" { value = aws_cloudfront_distribution.site.domain_name }
output "deploy_role_arn" { value = aws_iam_role.deploy.arn }
