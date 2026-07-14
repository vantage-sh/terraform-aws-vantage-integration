variable "cur_bucket_name" {
  type        = string
  description = "The S3 bucket name to provision for CUR integration. This module assumes the bucket does not already exist and will setup the bucket, CUR integration with the bucket, and access for the cross account role."
  default     = ""
}

variable "cur_bucket_region" {
  type        = string
  description = "The supported AWS region where the CUR bucket will be created. The AWS provider must use the same region."
  default     = "us-east-1"

  validation {
    condition = contains([
      "ap-southeast-1",
      "eu-west-1",
      "eu-west-2",
      "us-east-1",
      "us-west-2",
    ], var.cur_bucket_region)
    error_message = "cur_bucket_region must be one of: ap-southeast-1, eu-west-1, eu-west-2, us-east-1, us-west-2."
  }
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

variable "enforce_https_only" {
  type        = bool
  default     = true
  description = "Deny plain-HTTP S3 requests from non-AWS-service principals on the CUR bucket."
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
  description = "Optional override for the Vantage SNS topic used to notify Vantage of CUR bucket events. This should only be changed for module development."
  default     = null
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

variable "permissions_boundary_arn" {
  type        = string
  default     = null
  description = "The ARN of the IAM policy to use as the permissions boundary for the IAM role. If not set, no permissions boundary will be applied."

  validation {
    condition     = var.permissions_boundary_arn == null || can(regex("^arn:aws(-[a-z]+)?:iam::\\d{12}:policy/.+", var.permissions_boundary_arn))
    error_message = "If set, permissions_boundary_arn must be a valid IAM policy ARN."
  }
}
