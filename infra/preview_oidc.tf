# Separate deploy role for previews. Reuses the GitHub OIDC provider from
# github_oidc.tf but trusts pull_request-triggered runs (the prod role only
# trusts pushes to main, and would reject a PR workflow's token).
#
# Note on forks: GitHub does not issue an OIDC id-token to workflows triggered
# by pull_request from a fork, so this role can only be assumed by PRs from
# branches in the repo itself. For a personal repo that's exactly the desired
# blast radius - fork PRs simply won't get a preview.
data "aws_iam_policy_document" "preview_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:pull_request"]
    }
  }
}

resource "aws_iam_role" "preview_deploy" {
  name               = "${replace(var.domain_name, ".", "-")}-gha-preview"
  assume_role_policy = data.aws_iam_policy_document.preview_assume.json
}

# Least privilege: the preview bucket and the preview distribution only.
# Physically cannot write to, or invalidate, production.
data "aws_iam_policy_document" "preview_deploy" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.preview.arn]
  }
  statement {
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.preview.arn}/*"]
  }
  statement {
    # CreateInvalidation flushes the PR's path on deploy; GetInvalidation lets
    # the preview workflow wait for that invalidation to complete before it
    # smoke-tests the deployed URL, making the deployed-preview smoke test
    # deterministic instead of racing edge propagation. Still scoped to the
    # preview distribution only; cannot touch production.
    actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
    resources = [aws_cloudfront_distribution.preview.arn]
  }
}

resource "aws_iam_role_policy" "preview_deploy" {
  name   = "preview-deploy"
  role   = aws_iam_role.preview_deploy.id
  policy = data.aws_iam_policy_document.preview_deploy.json
}
