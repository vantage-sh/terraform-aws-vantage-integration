resource "aws_cur_report_definition" "vantage_cost_and_usage_reports" {
  count                      = var.cur_bucket_name != "" ? 1 : 0
  report_name                = var.cur_report_name
  time_unit                  = "DAILY"
  format                     = "textORcsv"
  compression                = "GZIP"
  additional_schema_elements = ["RESOURCES"]
  s3_bucket                  = aws_s3_bucket.vantage_cost_and_usage_reports[0].id
  s3_region                  = "us-east-1"
  s3_prefix                  = "daily-v1"
  report_versioning          = "OVERWRITE_REPORT"
  refresh_closed_reports     = true
  depends_on = [
    aws_s3_bucket_policy.vantage_cost_and_usage_reports
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
      identifiers = [aws_iam_role.vantage_cross_account_connection_with_bucket[0].arn]
    }

    resources = [
      "${aws_s3_bucket.vantage_cost_and_usage_reports[0].arn}/*"
    ]
  }
}

resource "aws_iam_role" "vantage_cross_account_connection_with_bucket" {
  count = var.cur_bucket_name != "" ? 1 : 0

  name               = "vantage_cross_account_connection"
  assume_role_policy = data.aws_iam_policy_document.vantage_assume_role.json
}

resource "aws_iam_policy" "vantage_cross_account_connection_with_bucket" {
  for_each = local.policies_with_bucket

  name   = each.key
  policy = each.value
}

resource "aws_iam_role_policy_attachment" "vantage_cross_account_connection_with_bucket" {
  for_each = local.policies_with_bucket

  role       = aws_iam_role.vantage_cross_account_connection_with_bucket[0].name
  policy_arn = aws_iam_policy.vantage_cross_account_connection_with_bucket[each.key].arn
}

resource "aws_iam_role_policy_attachment" "vantage_cross_account_connection_with_bucket_viewonly" {
  count      = var.cur_bucket_name != "" ? 1 : 0
  role       = aws_iam_role.vantage_cross_account_connection_with_bucket[0].name
  policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
}

resource "vantage_aws_provider" "with_bucket" {
  count = var.cur_bucket_name != "" ? 1 : 0

  cross_account_arn = aws_iam_role.vantage_cross_account_connection_with_bucket[0].arn
  bucket_arn        = aws_s3_bucket.vantage_cost_and_usage_reports[0].arn
}