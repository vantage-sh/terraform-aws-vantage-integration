variable "cur_bucket_name" {
  type        = string
  description = "The S3 bucket name to provision for CUR integration. This module assumes the bucket does not already exist and will setup the bucket, CUR integration with the bucket, and access for the cross account role."
  default     = ""
}

variable "cur_bucket_lifecycle_enabled" {
  type        = bool
  description = "Enable lifecycle configuration for the CUR bucket."
  default     = true
}

variable "cur_bucket_lifecycle_days" {
  type        = number
  description = "Number of days to retain CUR reports in the bucket."
  default     = 200
}

variable "cur_report_time_unit" {
  description = "The granularity of the cost and usage report: HOURLY or DAILY."
  type        = string
  default     = "DAILY"

  validation {
    condition     = contains(["HOURLY", "DAILY"], var.cur_report_time_unit)
    error_message = "cur_report_time_unit must be either 'HOURLY' or 'DAILY'."
  }
}

variable "vantage_sns_topic_arn" {
  type        = string
  description = "SNS Topic used to notify of bucket events, such as CUR files being updated. Default is the production SNS topic used by Vantage and should not be changed except for module development."
  default     = "arn:aws:sns:us-east-1:630399649041:cost-and-usage-report-uploaded"
}

variable "cur_report_name" {
  type        = string
  description = "Report name for the CUR report definition."
  default     = "VantageReport"
}

variable "compatibility_private_bucket_acl" {
  type        = bool
  description = "For backwards compatibility, users can set this variable to true so a 'private' bucket ACL is applied. This is not necessary for new buckets being created. If you're unsure, leave this as false."
  default     = false
}

variable "enable_autopilot" {
  type        = bool
  description = "Enable Vantage Autopilot. This will create more permissions for the cross account role."
  default     = true
}

variable "vantage_root_iam_policy_override" {
  type        = string
  description = "AWS IAM Policy to override the Vantage Root IAM policy."
  default     = null
}

variable "vantage_cloudwatch_metrics_iam_policy_override" {
  type        = string
  description = "AWS IAM Policy to override the Vantage Cloudwatch Metrics IAM policy."
  default     = null
}

variable "vantage_additional_resources_iam_policy_override" {
  type        = string
  description = "AWS IAM Policy to override the Vantage Additional ResourcesIAM policy."
  default     = null
}

variable "additional_inline_policies" {
  type        = set(map(string))
  description = "Additonal IAM Policies to include on the cross account role."
  default     = []
}

variable "tags" {
  description = "A map of tags to add to all supported resources managed by the module."
  type        = map(string)
  default     = {}
}

variable "cur_report_additional_schema_elements" {
  description = "A list of additional schema elements for the cur report. Only used if a cur bucket is specified."
  type        = list(string)
  default     = ["RESOURCES"]
}
