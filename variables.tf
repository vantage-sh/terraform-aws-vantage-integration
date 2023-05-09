variable "cur_bucket_name" {
  type        = string
  description = "The S3 bucket name to provision for CUR integration. This module assumes the bucket does not already exist and will setup the bucket, CUR integration with the bucket, and access for the cross account role."
  default     = ""
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
