resource "aws_s3_bucket" "vantage_cost_and_usage_reports" {
  count         = var.cur_bucket_name != "" ? 1 : 0
  bucket        = var.cur_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_acl" "vantage_cost_and_usage_reports" {
  count  = var.compatibility_private_bucket_acl ? 1 : 0
  bucket = aws_s3_bucket.vantage_cost_and_usage_reports[0].id
  acl    = "private"
}

resource "aws_s3_bucket_lifecycle_configuration" "vantage_cost_and_usage_reports" {
  count  = var.cur_bucket_name != "" ? 1 : 0
  bucket = aws_s3_bucket.vantage_cost_and_usage_reports[0].id

  rule {
    id = "remove-old-reports"

    expiration {
      days = 200
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