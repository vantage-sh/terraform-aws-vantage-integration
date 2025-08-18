terraform {
  required_providers {
    vantage = {
      source = "vantage-sh/vantage"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0.0, < 6.0.0"
    }
  }
  required_version = ">= 1.0.0"
}

data "vantage_aws_provider_info" "default" {
}

data "aws_iam_policy_document" "vantage_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [data.vantage_aws_provider_info.default.iam_role_arn]
    }
    condition {
      variable = "sts:ExternalId"
      test     = "StringEquals"
      values   = [data.vantage_aws_provider_info.default.external_id]
    }
  }
}

resource "aws_iam_role" "vantage_cross_account_connection_with_bucket" {
  count = var.cur_bucket_name != "" ? 1 : 0

  name                 = "vantage_cross_account_connection"
  assume_role_policy   = data.aws_iam_policy_document.vantage_assume_role.json
  permissions_boundary = var.permissions_boundary_arn

  inline_policy {
    name   = "VantageCostandUsageReportRetrieval"
    policy = data.aws_iam_policy_document.vantage_cur_retrieval[0].json
  }

  inline_policy {
    name   = "root"
    policy = var.vantage_root_iam_policy_override != null ? var.vantage_root_iam_policy_override : data.vantage_aws_provider_info.default.root_policy
  }

  dynamic "inline_policy" {
    for_each = var.enable_autopilot ? [1] : []
    content {
      name   = "VantageAutoPilot"
      policy = data.vantage_aws_provider_info.default.autopilot_policy
    }
  }

  inline_policy {
    name   = "VantageCloudWatchMetricsReadOnly"
    policy = var.vantage_cloudwatch_metrics_iam_policy_override != null ? var.vantage_cloudwatch_metrics_iam_policy_override : data.vantage_aws_provider_info.default.cloudwatch_metrics_policy
  }

  inline_policy {
    name   = "VantageAdditionalResourceReadOnly"
    policy = var.vantage_additional_resources_iam_policy_override != null ? var.vantage_additional_resources_iam_policy_override : data.vantage_aws_provider_info.default.additional_resources_policy
  }

  dynamic "inline_policy" {
    for_each = var.additional_inline_policies
    content {
      name   = inline_policy.value["name"]
      policy = inline_policy.value["policy"]
    }
  }

  tags = var.tags
}

resource "aws_iam_role" "vantage_cross_account_connection_without_bucket" {
  count                = var.cur_bucket_name != "" ? 0 : 1
  name                 = "vantage_cross_account_connection"
  assume_role_policy   = data.aws_iam_policy_document.vantage_assume_role.json
  permissions_boundary = var.permissions_boundary_arn

  inline_policy {
    name   = "root"
    policy = var.vantage_root_iam_policy_override != null ? var.vantage_root_iam_policy_override : data.vantage_aws_provider_info.default.root_policy
  }

  dynamic "inline_policy" {
    for_each = var.enable_autopilot ? [1] : []
    content {
      name   = "VantageAutoPilot"
      policy = data.vantage_aws_provider_info.default.autopilot_policy
    }
  }

  inline_policy {
    name   = "VantageCloudWatchMetricsReadOnly"
    policy = var.vantage_cloudwatch_metrics_iam_policy_override != null ? var.vantage_cloudwatch_metrics_iam_policy_override : data.vantage_aws_provider_info.default.cloudwatch_metrics_policy
  }

  inline_policy {
    name   = "VantageAdditionalResourceReadOnly"
    policy = var.vantage_additional_resources_iam_policy_override != null ? var.vantage_additional_resources_iam_policy_override : data.vantage_aws_provider_info.default.additional_resources_policy
  }

  dynamic "inline_policy" {
    for_each = var.additional_inline_policies
    content {
      name   = inline_policy.value["name"]
      policy = inline_policy.value["policy"]
    }
  }

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "vantage_cross_account_connection_with_bucket" {
  count      = var.cur_bucket_name != "" ? 1 : 0
  role       = aws_iam_role.vantage_cross_account_connection_with_bucket[0].name
  policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "vantage_cross_account_connection_without_bucket" {
  count      = var.cur_bucket_name != "" ? 0 : 1
  role       = aws_iam_role.vantage_cross_account_connection_without_bucket[0].name
  policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
}

resource "aws_cur_report_definition" "vantage_cost_and_usage_reports" {
  count                      = var.cur_bucket_name != "" ? 1 : 0
  report_name                = var.cur_report_name
  time_unit                  = var.cur_report_time_unit
  format                     = "textORcsv"
  compression                = "GZIP"
  additional_schema_elements = var.cur_report_additional_schema_elements
  s3_bucket                  = aws_s3_bucket.vantage_cost_and_usage_reports[0].id
  s3_region                  = "us-east-1"
  s3_prefix                  = "${lower(var.cur_report_time_unit)}-v1"
  report_versioning          = "OVERWRITE_REPORT"
  refresh_closed_reports     = true
  depends_on = [
    aws_s3_bucket_policy.vantage_cost_and_usage_reports
  ]
}

resource "aws_s3_bucket" "vantage_cost_and_usage_reports" {
  count         = var.cur_bucket_name != "" ? 1 : 0
  bucket        = var.cur_bucket_name
  force_destroy = true

  tags = var.tags
}

resource "aws_s3_bucket_acl" "vantage_cost_and_usage_reports" {
  count  = var.compatibility_private_bucket_acl ? 1 : 0
  bucket = aws_s3_bucket.vantage_cost_and_usage_reports[0].id
  acl    = "private"
}

resource "aws_s3_bucket_lifecycle_configuration" "vantage_cost_and_usage_reports" {
  count  = var.cur_bucket_name != "" && var.cur_bucket_lifecycle_enabled ? 1 : 0
  bucket = aws_s3_bucket.vantage_cost_and_usage_reports[0].id

  rule {
    id = "remove-old-reports"

    expiration {
      days = var.cur_bucket_lifecycle_days
    }

    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "vantage_cost_and_usage_reports" {
  count                   = var.cur_bucket_name != "" ? 1 : 0
  bucket                  = aws_s3_bucket.vantage_cost_and_usage_reports[0].id
  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true
  ignore_public_acls      = true
}

resource "aws_s3_bucket_policy" "vantage_cost_and_usage_reports" {
  count  = var.cur_bucket_name != "" ? 1 : 0
  bucket = aws_s3_bucket.vantage_cost_and_usage_reports[0].id
  policy = data.aws_iam_policy_document.vantage_cur_access[0].json
  depends_on = [
    aws_s3_bucket_public_access_block.vantage_cost_and_usage_reports
  ]
}

resource "aws_s3_bucket_notification" "vantage_cost_and_usage_reports" {
  count  = var.cur_bucket_name != "" ? 1 : 0
  bucket = aws_s3_bucket.vantage_cost_and_usage_reports[0].id
  topic {
    topic_arn     = var.vantage_sns_topic_arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".csv.gz"
  }
  depends_on = [
    aws_s3_bucket.vantage_cost_and_usage_reports
  ]
}

data "aws_iam_policy_document" "vantage_cur_retrieval" {
  count = var.cur_bucket_name != "" ? 1 : 0
  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectAcl"
    ]

    resources = [
      "${aws_s3_bucket.vantage_cost_and_usage_reports[0].arn}/*"
    ]
  }
}

data "aws_iam_policy_document" "vantage_cur_access" {
  count = var.cur_bucket_name != "" ? 1 : 0

  statement {
    effect = "Allow"

    actions = [
      "s3:GetBucketAcl",
      "s3:GetBucketPolicy"
    ]
    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }

    resources = [
      "${aws_s3_bucket.vantage_cost_and_usage_reports[0].arn}"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:PutObject"
    ]
    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }

    resources = [
      "${aws_s3_bucket.vantage_cost_and_usage_reports[0].arn}/*"
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectAcl"
    ]
    principals {
      type        = "AWS"
      identifiers = ["${aws_iam_role.vantage_cross_account_connection_with_bucket[0].arn}"]
    }

    resources = [
      "${aws_s3_bucket.vantage_cost_and_usage_reports[0].arn}/*"
    ]
  }
}

resource "vantage_aws_provider" "with_bucket" {
  count = var.cur_bucket_name != "" ? 1 : 0

  cross_account_arn = aws_iam_role.vantage_cross_account_connection_with_bucket[0].arn
  bucket_arn        = aws_s3_bucket.vantage_cost_and_usage_reports[0].arn
}

resource "vantage_aws_provider" "without_bucket" {
  count = var.cur_bucket_name != "" ? 0 : 1

  cross_account_arn = aws_iam_role.vantage_cross_account_connection_without_bucket[0].arn
}
