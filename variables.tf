variable "cur_bucket_name" {
  type        = string
  description = "The S3 bucket name to provision for CUR integration. This module assumes the bucket does not already exist and will setup the bucket, CUR integration with the bucket, and access for the cross account role. Cannot be combined with existing_cur_bucket_name."
  default     = ""
}

variable "existing_cur_bucket_name" {
  type        = string
  description = "Name of an S3 bucket that already exists, used instead of cur_bucket_name. The module looks the bucket up and does not create or delete it, or change its lifecycle rules, ACL, or public access block. The bucket must be in cur_bucket_region. Cannot be combined with cur_bucket_name."
  default     = ""

  validation {
    condition     = !(var.cur_bucket_name != "" && var.existing_cur_bucket_name != "")
    error_message = "Only one of cur_bucket_name or existing_cur_bucket_name may be set."
  }
}

variable "existing_cur_bucket_manage_policy" {
  type        = bool
  description = "Whether to manage the bucket policy on existing_cur_bucket_name. Defaults to true when this module creates the CUR report, because AWS billing needs the policy to write, and false when cur_report_enabled is false. Set true or false to override that default. Managing the policy replaces the bucket policy. Statements in existing_cur_bucket_policy_json are kept, and Vantage statements override statements with the same Sid."
  default     = null
}

variable "existing_cur_bucket_policy_json" {
  type        = string
  description = "JSON policy document whose Statement array is merged into the managed bucket policy for existing_cur_bucket_name. Vantage statements override statements with the same Sid. Statements without a Sid are kept. Only used when the module manages the policy."
  default     = null

  validation {
    condition = var.existing_cur_bucket_policy_json == null || (
      can(jsondecode(var.existing_cur_bucket_policy_json).Statement) &&
      (
        try(length(jsondecode(var.existing_cur_bucket_policy_json).Statement), -1) == 0 ||
        can(jsondecode(var.existing_cur_bucket_policy_json).Statement[0])
      )
    )
    error_message = "existing_cur_bucket_policy_json must be a JSON policy document with a Statement array."
  }

  validation {
    condition = var.existing_cur_bucket_policy_json == null || (
      var.existing_cur_bucket_name != "" && (
        var.existing_cur_bucket_manage_policy != null ? var.existing_cur_bucket_manage_policy : var.cur_report_enabled
      )
    )
    error_message = "existing_cur_bucket_policy_json is only applied when the module manages the policy on existing_cur_bucket_name. Set existing_cur_bucket_manage_policy to true."
  }
}

variable "existing_cur_bucket_manage_notification" {
  type        = bool
  description = "Whether to manage the S3 event notification configuration on existing_cur_bucket_name. Defaults to true. S3 allows one notification configuration per bucket, so managing it replaces the bucket's notifications with the Vantage topic plus existing_cur_bucket_additional_notifications. Set to false to leave notifications unchanged."
  default     = true
}

variable "existing_cur_bucket_notification_eventbridge" {
  type        = bool
  description = "Whether the managed notification configuration on existing_cur_bucket_name keeps Amazon EventBridge enabled. When false, that configuration turns EventBridge off. Requires existing_cur_bucket_manage_notification."
  default     = false

  validation {
    condition     = !var.existing_cur_bucket_notification_eventbridge || (var.existing_cur_bucket_name != "" && var.existing_cur_bucket_manage_notification)
    error_message = "existing_cur_bucket_notification_eventbridge only applies when the module manages the notification on existing_cur_bucket_name."
  }
}

variable "existing_cur_bucket_additional_notifications" {
  type = object({
    topics = optional(list(object({
      id            = optional(string)
      topic_arn     = string
      events        = list(string)
      filter_prefix = optional(string)
      filter_suffix = optional(string)
    })), [])
    queues = optional(list(object({
      id            = optional(string)
      queue_arn     = string
      events        = list(string)
      filter_prefix = optional(string)
      filter_suffix = optional(string)
    })), [])
    lambda_functions = optional(list(object({
      id                  = optional(string)
      lambda_function_arn = string
      events              = list(string)
      filter_prefix       = optional(string)
      filter_suffix       = optional(string)
    })), [])
  })
  description = "SNS, SQS, and Lambda notifications to keep on existing_cur_bucket_name alongside the Vantage topic. Requires existing_cur_bucket_manage_notification."
  default     = {}

  validation {
    condition = (
      length(coalesce(try(var.existing_cur_bucket_additional_notifications.topics, null), [])) == 0 &&
      length(coalesce(try(var.existing_cur_bucket_additional_notifications.queues, null), [])) == 0 &&
      length(coalesce(try(var.existing_cur_bucket_additional_notifications.lambda_functions, null), [])) == 0
    ) || (var.existing_cur_bucket_name != "" && var.existing_cur_bucket_manage_notification)
    error_message = "existing_cur_bucket_additional_notifications only apply when the module manages the notification on existing_cur_bucket_name."
  }
}

variable "existing_cur_bucket_kms_key_arn" {
  type        = string
  description = "KMS key ARN for an SSE-KMS existing CUR bucket. Grants the cross-account role kms:Decrypt on this key."
  default     = null

  validation {
    condition     = var.existing_cur_bucket_kms_key_arn == null || can(regex("^arn:aws(-[a-z]+)?:kms:[a-z0-9-]+:\\d{12}:(key|alias)/.+$", var.existing_cur_bucket_kms_key_arn))
    error_message = "existing_cur_bucket_kms_key_arn must be a KMS key or alias ARN."
  }

  validation {
    condition     = var.existing_cur_bucket_kms_key_arn == null || var.existing_cur_bucket_name != ""
    error_message = "existing_cur_bucket_kms_key_arn requires existing_cur_bucket_name."
  }
}

variable "cur_bucket_region" {
  type        = string
  description = "The supported AWS region where the CUR bucket will be created, or where existing_cur_bucket_name is located. The AWS provider must use the same region."
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

variable "cur_bucket_lifecycle_rules" {
  type = list(object({
    id              = string
    enabled         = optional(bool, true)
    prefix          = optional(string)
    expiration_days = optional(number)
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
  }))
  description = "Advanced lifecycle rules for the CUR bucket. Set to [] to disable lifecycle configuration. When null, cur_bucket_lifecycle_enabled and cur_bucket_lifecycle_days configure the default rule."
  default     = null

  validation {
    condition = var.cur_bucket_lifecycle_rules == null ? true : alltrue([
      for rule in var.cur_bucket_lifecycle_rules :
      try(rule.expiration_days, null) != null || length(try(rule.transitions, [])) > 0
    ])
    error_message = "Each cur_bucket_lifecycle_rules entry must set expiration_days and/or at least one transition."
  }

  validation {
    condition     = var.existing_cur_bucket_name == "" || var.cur_bucket_lifecycle_rules == null
    error_message = "cur_bucket_lifecycle_rules only apply to a bucket this module creates. The module does not change lifecycle rules on existing_cur_bucket_name."
  }
}

variable "cur_bucket_lifecycle_enabled" {
  type        = bool
  description = "Whether to create the default CUR bucket lifecycle rule when cur_bucket_lifecycle_rules is null."
  default     = true
}

variable "cur_bucket_lifecycle_days" {
  type        = number
  description = "Retention period, in days, for the default CUR bucket lifecycle rule when cur_bucket_lifecycle_rules is null."
  default     = 200
}

variable "enforce_https_only" {
  type        = bool
  default     = null
  description = "Deny plain-HTTP S3 requests from non-AWS-service principals on the CUR bucket. Defaults to true when this module creates the bucket and false for an existing bucket, where the deny would apply to every client of the bucket. AWS billing report delivery is exempt via aws:PrincipalIsAWSService."

  validation {
    condition = !(var.existing_cur_bucket_name != "" && var.enforce_https_only == true) || (
      var.existing_cur_bucket_manage_policy != null ? var.existing_cur_bucket_manage_policy : var.cur_report_enabled
    )
    error_message = "enforce_https_only = true adds a statement to the bucket policy, but the module is not managing the policy on existing_cur_bucket_name. Set existing_cur_bucket_manage_policy to true."
  }
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

variable "cur_report_s3_prefix" {
  type        = string
  description = "S3 prefix for the managed CUR report. Defaults to <time unit>-v1, for example daily-v1. On an existing bucket, the Vantage notification filter and the cross-account role's s3:GetObject access are limited to this prefix. When cur_report_enabled is false and this is unset, both cover the whole bucket."
  default     = null

  validation {
    condition = var.cur_report_s3_prefix == null || (
      length(var.cur_report_s3_prefix) > 0 &&
      length(var.cur_report_s3_prefix) <= 256 &&
      can(regex("^[0-9A-Za-z!\\-_.*'()/]+$", var.cur_report_s3_prefix)) &&
      !startswith(var.cur_report_s3_prefix, "/") &&
      !endswith(var.cur_report_s3_prefix, "/")
    )
    error_message = "cur_report_s3_prefix must be 1-256 characters, contain only letters, numbers, and !-_.*'()/, and must not start or end with a slash."
  }
}

variable "cur_report_name" {
  type        = string
  description = "Name of the managed CUR report."
  default     = "VantageReport"
}

variable "cur_report_enabled" {
  type        = bool
  description = "Whether to create a CUR report. Set to false when managing the report separately."
  default     = true
}

variable "upgrade_to_cur_2" {
  type        = bool
  description = "Whether to replace the legacy CUR 1.0 report definition with a CUR 2.0 data export."
  default     = false
}

variable "compatibility_private_bucket_acl" {
  type        = bool
  description = "For backwards compatibility, users can set this variable to true so a 'private' bucket ACL is applied. This is not necessary for new buckets being created. If you're unsure, leave this as false."
  default     = false

  validation {
    condition     = var.existing_cur_bucket_name == "" || !var.compatibility_private_bucket_acl
    error_message = "compatibility_private_bucket_acl only applies to a bucket this module creates. The module does not change the ACL on existing_cur_bucket_name."
  }
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

variable "permissions_boundary_arn" {
  type        = string
  default     = null
  description = "The ARN of the IAM policy to use as the permissions boundary for the IAM role. If not set, no permissions boundary will be applied."

  validation {
    condition     = var.permissions_boundary_arn == null || can(regex("^arn:aws(-[a-z]+)?:iam::\\d{12}:policy/.+", var.permissions_boundary_arn))
    error_message = "If set, permissions_boundary_arn must be a valid IAM policy ARN."
  }
}
