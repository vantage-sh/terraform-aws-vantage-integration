# State renames from the former with_bucket / without_bucket resource split.
# Terraform forbids two moved blocks with the same destination, so chain through
# the without_bucket address (HashiCorp's mutually exclusive move pattern):
#   with_bucket -> without_bucket -> final
#   without_bucket -> final
# Only one old address exists in a given state.

moved {
  from = aws_iam_role.vantage_cross_account_connection_with_bucket[0]
  to   = aws_iam_role.vantage_cross_account_connection_without_bucket[0]
}

moved {
  from = aws_iam_role.vantage_cross_account_connection_without_bucket[0]
  to   = aws_iam_role.vantage_cross_account_connection
}

moved {
  from = aws_iam_role_policy.vantage_root_with_bucket[0]
  to   = aws_iam_role_policy.vantage_root_without_bucket[0]
}

moved {
  from = aws_iam_role_policy.vantage_root_without_bucket[0]
  to   = aws_iam_role_policy.vantage_root
}

moved {
  from = aws_iam_role_policy.vantage_cloudwatch_metrics_with_bucket[0]
  to   = aws_iam_role_policy.vantage_cloudwatch_metrics_without_bucket[0]
}

moved {
  from = aws_iam_role_policy.vantage_cloudwatch_metrics_without_bucket[0]
  to   = aws_iam_role_policy.vantage_cloudwatch_metrics
}

moved {
  from = aws_iam_role_policy.vantage_additional_resources_with_bucket[0]
  to   = aws_iam_role_policy.vantage_additional_resources_without_bucket[0]
}

moved {
  from = aws_iam_role_policy.vantage_additional_resources_without_bucket[0]
  to   = aws_iam_role_policy.vantage_additional_resources
}

moved {
  from = aws_iam_role_policy_attachment.vantage_cross_account_connection_with_bucket[0]
  to   = aws_iam_role_policy_attachment.vantage_cross_account_connection_without_bucket[0]
}

moved {
  from = aws_iam_role_policy_attachment.vantage_cross_account_connection_without_bucket[0]
  to   = aws_iam_role_policy_attachment.vantage_cross_account_connection
}

moved {
  from = vantage_aws_provider.with_bucket[0]
  to   = vantage_aws_provider.without_bucket[0]
}

moved {
  from = vantage_aws_provider.without_bucket[0]
  to   = vantage_aws_provider.this
}

moved {
  from = aws_iam_role_policy.vantage_autopilot_with_bucket[0]
  to   = aws_iam_role_policy.vantage_autopilot_without_bucket[0]
}

moved {
  from = aws_iam_role_policy.vantage_autopilot_without_bucket[0]
  to   = aws_iam_role_policy.vantage_autopilot[0]
}

moved {
  from = aws_iam_role_policy.additional_inline_policies_with_bucket
  to   = aws_iam_role_policy.additional_inline_policies_without_bucket
}

moved {
  from = aws_iam_role_policy.additional_inline_policies_without_bucket
  to   = aws_iam_role_policy.additional_inline_policies
}
