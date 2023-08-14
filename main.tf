data "vantage_aws_provider_info" "default" {
}

locals {
  policies_without_bucket = var.cur_bucket_name != "" ? {} : {
    VantageRootPolicy = var.vantage_root_iam_policy_override != null ? var.vantage_root_iam_policy_override : data.vantage_aws_provider_info.default.root_policy,
    VantageCloudWatchMetricsReadOnly = var.vantage_cloudwatch_metrics_iam_policy_override != null ? var.vantage_cloudwatch_metrics_iam_policy_override : data.vantage_aws_provider_info.default.cloudwatch_metrics_policy,
    VantageAdditionalResourceReadOnly = var.vantage_additional_resources_iam_policy_override != null ? var.vantage_additional_resources_iam_policy_override : data.vantage_aws_provider_info.default.additional_resources_policy,
    VantageAutoPilot = var.enable_autopilot ? data.vantage_aws_provider_info.default.autopilot_policy : null
  }

  policies_with_bucket = var.cur_bucket_name != "" ? {
    VantageRootPolicy = var.vantage_root_iam_policy_override != null ? var.vantage_root_iam_policy_override : data.vantage_aws_provider_info.default.root_policy,
    VantageCloudWatchMetricsReadOnly = var.vantage_cloudwatch_metrics_iam_policy_override != null ? var.vantage_cloudwatch_metrics_iam_policy_override : data.vantage_aws_provider_info.default.cloudwatch_metrics_policy,
    VantageAdditionalResourceReadOnly = var.vantage_additional_resources_iam_policy_override != null ? var.vantage_additional_resources_iam_policy_override : data.vantage_aws_provider_info.default.additional_resources_policy,
    VantageAutoPilot = var.enable_autopilot ? data.vantage_aws_provider_info.default.autopilot_policy : null,
    VantageCostandUsageReportRetrieval = data.aws_iam_policy_document.vantage_cur_retrieval[0].json
  } : {}
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

output "test" {
  value = data.vantage_aws_provider_info.default.root_policy
}