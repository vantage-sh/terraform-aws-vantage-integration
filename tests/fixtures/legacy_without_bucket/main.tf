# Minimal stand-in for the pre-unification member-account resource addresses.
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    vantage = {
      source = "vantage-sh/vantage"
    }
  }
}

resource "aws_iam_role" "vantage_cross_account_connection_without_bucket" {
  count = 1

  name = "vantage_cross_account_connection"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::630399649041:role/vantage" }
    }]
  })
}

resource "aws_iam_role_policy" "vantage_root_without_bucket" {
  count = 1

  name   = "root"
  role   = aws_iam_role.vantage_cross_account_connection_without_bucket[0].name
  policy = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
}

resource "aws_iam_role_policy" "vantage_cloudwatch_metrics_without_bucket" {
  count = 1

  name   = "VantageCloudWatchMetricsReadOnly"
  role   = aws_iam_role.vantage_cross_account_connection_without_bucket[0].name
  policy = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
}

resource "aws_iam_role_policy" "vantage_additional_resources_without_bucket" {
  count = 1

  name   = "VantageAdditionalResourceReadOnly"
  role   = aws_iam_role.vantage_cross_account_connection_without_bucket[0].name
  policy = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
}

resource "aws_iam_role_policy" "vantage_autopilot_without_bucket" {
  count = 1

  name   = "VantageAutoPilot"
  role   = aws_iam_role.vantage_cross_account_connection_without_bucket[0].name
  policy = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
}

resource "aws_iam_role_policy" "additional_inline_policies_without_bucket" {
  for_each = {
    extra = {
      name   = "extra"
      policy = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  name   = each.value.name
  role   = aws_iam_role.vantage_cross_account_connection_without_bucket[0].name
  policy = each.value.policy
}

resource "aws_iam_role_policy_attachment" "vantage_cross_account_connection_without_bucket" {
  count = 1

  role       = aws_iam_role.vantage_cross_account_connection_without_bucket[0].name
  policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
}

resource "vantage_aws_provider" "without_bucket" {
  count = 1

  cross_account_arn = aws_iam_role.vantage_cross_account_connection_without_bucket[0].arn
}

output "role_id" {
  value = aws_iam_role.vantage_cross_account_connection_without_bucket[0].id
}

output "provider_id" {
  value = vantage_aws_provider.without_bucket[0].id
}
