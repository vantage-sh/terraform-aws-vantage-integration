output "vantage_cross_account_connection_role_arn" {
  description = "The Vantage cross account connection IAM role ARN"
  value       = try(var.cur_bucket_name != "" ? aws_iam_role.vantage_cross_account_connection_with_bucket[0].arn : aws_iam_role.vantage_cross_account_connection_without_bucket[0].arn, null)
}

output "vantage_cost_and_usage_report_arn" {
  description = "The Vantage CUR arn"
  value       = try(aws_cur_report_definition.vantage_cost_and_usage_reports.arn, null)
}

output "vantage_cost_and_usage_report_name" {
  description = "The Vantage CUR name"
  value       = try(aws_cur_report_definition.vantage_cost_and_usage_reports.report_name, null)
}

output "vantage_cost_and_usage_reports_bucket_arn" {
  description = "The Vantage CUR bucket ARN"
  value       = try(aws_s3_bucket.vantage_cost_and_usage_reports.arn, null)
}

output "vantage_cost_and_usage_reports_bucket_id" {
  description = "The Vantage CUR bucket ID"
  value       = try(aws_s3_bucket.vantage_cost_and_usage_reports.id, null)
}
