# GitHub Actions assumes this role via OIDC, no long-lived AWS keys stored.
# The OIDC provider is account-wide and already exists (created once by the
# reecewall.dev hub), so reference it here rather than creating a duplicate.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name               = "${replace(var.domain_name, ".", "-")}-gha-deploy"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# Least privilege: write the bucket, invalidate this distribution. Nothing else.
data "aws_iam_policy_document" "deploy" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.site.arn]
  }
  statement {
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]
  }
  statement {
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.site.arn]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

# The scheduled pipeline (pipeline_azure.yml) self-publishes fresh data to the
# edge: a scoped `aws s3 sync` of the data/ prefix + an invalidation of /data/*.
# It runs on the same branch as the deploy role, so it reuses the assume policy,
# but it gets its OWN role with a strictly narrower policy: it may only touch the
# data/ prefix and invalidate this one distribution. It can never overwrite the
# rest of the site (that stays the deploy role's job, on code change).
resource "aws_iam_role" "data_publish" {
  name               = "${replace(var.domain_name, ".", "-")}-gha-data-publish"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "data_publish" {
  # `aws s3 sync` lists the destination to diff before uploading; scope that
  # listing to the data/ prefix so the role cannot enumerate the whole site.
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.site.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["data/*"]
    }
  }
  # Write and prune only under data/ (the sync runs with --delete so it can clear
  # an artifact that is no longer produced). Both are confined to the data/ prefix,
  # so the role can never touch the rest of the site.
  statement {
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.site.arn}/data/*"]
  }
  statement {
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.site.arn]
  }
}

resource "aws_iam_role_policy" "data_publish" {
  name   = "data-publish"
  role   = aws_iam_role.data_publish.id
  policy = data.aws_iam_policy_document.data_publish.json
}
