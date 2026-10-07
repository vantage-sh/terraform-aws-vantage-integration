terraform {
  required_providers {
    # tflint-ignore: terraform_required_providers
    vantage = {
      source = "vantage-sh/vantage"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.48.0"
    }
  }
  required_version = ">= 1.3.0"
}

data "aws_caller_identity" "current" {
  lifecycle {
    precondition {
      condition     = var.cur_bucket_name == "" || var.existing_cur_bucket_name == ""
      error_message = "Set cur_bucket_name to create a CUR bucket or existing_cur_bucket_name to use a bucket you already have, not both."
    }

    precondition {
      condition     = var.existing_cur_bucket_kms_key_arn == null || var.existing_cur_bucket_name != ""
      error_message = "existing_cur_bucket_kms_key_arn requires existing_cur_bucket_name."
    }

    precondition {
      condition = var.existing_cur_bucket_policy_json == null || (
        var.existing_cur_bucket_name != "" && (
          var.existing_cur_bucket_manage_policy != null ? var.existing_cur_bucket_manage_policy : var.cur_report_enabled
        )
      )
      error_message = "existing_cur_bucket_policy_json is only applied when the module manages the policy on existing_cur_bucket_name. Set existing_cur_bucket_manage_policy to true."
    }
  }
}
data "aws_partition" "current" {}

# bucket_regional_domain_name is the bucket's real region on AWS provider v5 and v6.
# v6 reused the region attribute for the provider region.
data "aws_s3_bucket" "existing_cur_bucket" {
  count  = local.use_existing_cur_bucket ? 1 : 0
  bucket = var.existing_cur_bucket_name

  lifecycle {
    postcondition {
      condition     = endswith(self.bucket_regional_domain_name, ".s3.${var.cur_bucket_region}.amazonaws.com")
      error_message = "S3 bucket ${var.existing_cur_bucket_name} is not in ${var.cur_bucket_region}. cur_bucket_region must be the bucket's region, and the AWS provider region must match. This check runs even when the module does not manage the bucket notification."
    }
  }
}

locals {
  account_id = data.aws_caller_identity.current.account_id

  create_cur_bucket       = var.cur_bucket_name != ""
  use_existing_cur_bucket = var.existing_cur_bucket_name != ""
  cur_bucket_enabled      = local.create_cur_bucket || local.use_existing_cur_bucket

  # Null means: manage the policy when this module creates the report, because AWS
  # billing needs a bucket policy to write. A self-managed report leaves the policy alone.
  manage_existing_cur_bucket_policy = local.use_existing_cur_bucket && (
    var.existing_cur_bucket_manage_policy != null ? var.existing_cur_bucket_manage_policy : var.cur_report_enabled
  )
  manage_existing_cur_bucket_notification = local.use_existing_cur_bucket && var.existing_cur_bucket_manage_notification

  # True for a bucket this module creates. False for an existing bucket, where the
  # deny would apply to every client of that bucket.
  enforce_https_only = var.enforce_https_only != null ? var.enforce_https_only : local.create_cur_bucket

  # Include billing write statements for module-created buckets, and for an existing
  # bucket only when this module creates the report. A forced policy on a self-managed
  # report matches the existing-bucket CloudFormation template: the cross-account read
  # statement only.
  include_cur_billing_policy_statements = local.create_cur_bucket || (local.use_existing_cur_bucket && var.cur_report_enabled)

  cur_report_s3_prefix = var.cur_report_s3_prefix != null ? var.cur_report_s3_prefix : "${lower(var.cur_report_time_unit)}-v1"
  # Unset prefix on a self-managed report covers the whole existing bucket.
  existing_cur_object_prefix = var.cur_report_s3_prefix != null ? var.cur_report_s3_prefix : (
    var.cur_report_enabled ? local.cur_report_s3_prefix : ""
  )

  cur_bucket_id = local.create_cur_bucket ? aws_s3_bucket.vantage_cost_and_usage_reports[0].id : (
    local.use_existing_cur_bucket ? data.aws_s3_bucket.existing_cur_bucket[0].id : null
  )
  cur_bucket_arn = local.create_cur_bucket ? aws_s3_bucket.vantage_cost_and_usage_reports[0].arn : (
    local.use_existing_cur_bucket ? data.aws_s3_bucket.existing_cur_bucket[0].arn : null
  )
  cur_object_arn = local.cur_bucket_arn == null ? null : (
    local.use_existing_cur_bucket && local.existing_cur_object_prefix != "" ? "${local.cur_bucket_arn}/${local.existing_cur_object_prefix}/*" : "${local.cur_bucket_arn}/*"
  )

  additional_cur_notification_topics  = coalesce(try(var.existing_cur_bucket_additional_notifications.topics, null), [])
  additional_cur_notification_queues  = coalesce(try(var.existing_cur_bucket_additional_notifications.queues, null), [])
  additional_cur_notification_lambdas = coalesce(try(var.existing_cur_bucket_additional_notifications.lambda_functions, null), [])

  vantage_sns_topic_arns = {
    ap-southeast-1 = "arn:aws:sns:ap-southeast-1:630399649041:cost-and-usage-report-uploaded"
    eu-west-1      = "arn:aws:sns:eu-west-1:630399649041:cost-and-usage-report-uploaded"
    eu-west-2      = "arn:aws:sns:eu-west-2:630399649041:cost-and-usage-report-uploaded"
    us-east-1      = "arn:aws:sns:us-east-1:630399649041:cost-and-usage-report-uploaded"
    us-west-2      = "arn:aws:sns:us-west-2:630399649041:cost-and-usage-report-uploaded"
  }
  vantage_sns_topic_arn = var.vantage_sns_topic_arn != null ? var.vantage_sns_topic_arn : local.vantage_sns_topic_arns[var.cur_bucket_region]

  # Prefer explicit lifecycle rules when set (including [] to disable). Otherwise use
  # the simple enabled/days settings so existing module callers remain unchanged.
  cur_bucket_lifecycle_rules = var.cur_bucket_lifecycle_rules != null ? var.cur_bucket_lifecycle_rules : (
    var.cur_bucket_lifecycle_enabled ? [
      {
        id              = "remove-old-reports"
        enabled         = true
        prefix          = null
        expiration_days = var.cur_bucket_lifecycle_days
        transitions     = []
      }
    ] : []
  )
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
  count = local.cur_bucket_enabled ? 1 : 0

  name                 = "vantage_cross_account_connection"
  assume_role_policy   = data.aws_iam_policy_document.vantage_assume_role.json
  permissions_boundary = var.permissions_boundary_arn

  tags = var.tags
}

resource "aws_iam_role" "vantage_cross_account_connection_without_bucket" {
  count                = local.cur_bucket_enabled ? 0 : 1
  name                 = "vantage_cross_account_connection"
  assume_role_policy   = data.aws_iam_policy_document.vantage_assume_role.json
  permissions_boundary = var.permissions_boundary_arn

  tags = var.tags
}

resource "aws_iam_role_policy" "vantage_cur_retrieval" {
  count = local.cur_bucket_enabled ? 1 : 0

  name   = "VantageCostandUsageReportRetrieval"
  role   = aws_iam_role.vantage_cross_account_connection_with_bucket[0].name
  policy = data.aws_iam_policy_document.vantage_cur_retrieval[0].json
}

resource "aws_iam_role_policy" "vantage_root_with_bucket" {
  count = local.cur_bucket_enabled ? 1 : 0

  name   = "root"
  role   = aws_iam_role.vantage_cross_account_connection_with_bucket[0].name
  policy = var.vantage_root_iam_policy_override != null ? var.vantage_root_iam_policy_override : data.vantage_aws_provider_info.default.root_policy
}

resource "aws_iam_role_policy" "vantage_root_without_bucket" {
  count = local.cur_bucket_enabled ? 0 : 1

  name   = "root"
  role   = aws_iam_role.vantage_cross_account_connection_without_bucket[0].name
  policy = var.vantage_root_iam_policy_override != null ? var.vantage_root_iam_policy_override : data.vantage_aws_provider_info.default.root_policy
}

resource "aws_iam_role_policy" "vantage_autopilot_with_bucket" {
  count = local.cur_bucket_enabled && var.enable_autopilot ? 1 : 0

  name   = "VantageAutoPilot"
  role   = aws_iam_role.vantage_cross_account_connection_with_bucket[0].name
  policy = data.vantage_aws_provider_info.default.autopilot_policy
}

resource "aws_iam_role_policy" "vantage_autopilot_without_bucket" {
  count = !local.cur_bucket_enabled && var.enable_autopilot ? 1 : 0

  name   = "VantageAutoPilot"
  role   = aws_iam_role.vantage_cross_account_connection_without_bucket[0].name
  policy = data.vantage_aws_provider_info.default.autopilot_policy
}

resource "aws_iam_role_policy" "vantage_cloudwatch_metrics_with_bucket" {
  count = local.cur_bucket_enabled ? 1 : 0

  name   = "VantageCloudWatchMetricsReadOnly"
  role   = aws_iam_role.vantage_cross_account_connection_with_bucket[0].name
  policy = var.vantage_cloudwatch_metrics_iam_policy_override != null ? var.vantage_cloudwatch_metrics_iam_policy_override : data.vantage_aws_provider_info.default.cloudwatch_metrics_policy
}

resource "aws_iam_role_policy" "vantage_cloudwatch_metrics_without_bucket" {
  count = local.cur_bucket_enabled ? 0 : 1

  name   = "VantageCloudWatchMetricsReadOnly"
  role   = aws_iam_role.vantage_cross_account_connection_without_bucket[0].name
  policy = var.vantage_cloudwatch_metrics_iam_policy_override != null ? var.vantage_cloudwatch_metrics_iam_policy_override : data.vantage_aws_provider_info.default.cloudwatch_metrics_policy
}

resource "aws_iam_role_policy" "vantage_additional_resources_with_bucket" {
  count = local.cur_bucket_enabled ? 1 : 0

  name   = "VantageAdditionalResourceReadOnly"
  role   = aws_iam_role.vantage_cross_account_connection_with_bucket[0].name
  policy = var.vantage_additional_resources_iam_policy_override != null ? var.vantage_additional_resources_iam_policy_override : data.vantage_aws_provider_info.default.additional_resources_policy
}

resource "aws_iam_role_policy" "vantage_additional_resources_without_bucket" {
  count = local.cur_bucket_enabled ? 0 : 1

  name   = "VantageAdditionalResourceReadOnly"
  role   = aws_iam_role.vantage_cross_account_connection_without_bucket[0].name
  policy = var.vantage_additional_resources_iam_policy_override != null ? var.vantage_additional_resources_iam_policy_override : data.vantage_aws_provider_info.default.additional_resources_policy
}

resource "aws_iam_role_policy" "additional_inline_policies_with_bucket" {
  for_each = local.cur_bucket_enabled ? { for additional_policy in var.additional_inline_policies : additional_policy["name"] => additional_policy } : {}

  name   = each.value["name"]
  role   = aws_iam_role.vantage_cross_account_connection_with_bucket[0].name
  policy = each.value["policy"]
}

resource "aws_iam_role_policy" "additional_inline_policies_without_bucket" {
  for_each = !local.cur_bucket_enabled ? { for additional_policy in var.additional_inline_policies : additional_policy["name"] => additional_policy } : {}

  name   = each.value["name"]
  role   = aws_iam_role.vantage_cross_account_connection_without_bucket[0].name
  policy = each.value["policy"]
}

resource "aws_iam_role_policy_attachment" "vantage_cross_account_connection_with_bucket" {
  count      = local.cur_bucket_enabled ? 1 : 0
  role       = aws_iam_role.vantage_cross_account_connection_with_bucket[0].name
  policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "vantage_cross_account_connection_without_bucket" {
  count      = local.cur_bucket_enabled ? 0 : 1
  role       = aws_iam_role.vantage_cross_account_connection_without_bucket[0].name
  policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
}

resource "aws_cur_report_definition" "vantage_cost_and_usage_reports" {
  count                      = local.cur_bucket_enabled && var.cur_report_enabled && !var.upgrade_to_cur_2 ? 1 : 0
  report_name                = var.cur_report_name
  time_unit                  = var.cur_report_time_unit
  format                     = "textORcsv"
  compression                = "GZIP"
  additional_schema_elements = ["RESOURCES"]
  s3_bucket                  = local.cur_bucket_id
  s3_region                  = var.cur_bucket_region
  s3_prefix                  = local.cur_report_s3_prefix
  report_versioning          = "OVERWRITE_REPORT"
  refresh_closed_reports     = true

  depends_on = [
    aws_s3_bucket_policy.vantage_cost_and_usage_reports,
    aws_s3_bucket_policy.existing_cur_bucket,
  ]
}

resource "aws_bcmdataexports_export" "vantage_cost_and_usage_reports" {
  count = local.cur_bucket_enabled && var.cur_report_enabled && var.upgrade_to_cur_2 ? 1 : 0

  export {
    name = var.cur_report_name

    data_query {
      query_statement = "SELECT bill_bill_type, bill_billing_entity, bill_billing_period_end_date, bill_billing_period_start_date, bill_invoice_id, bill_invoicing_entity, bill_payer_account_id, bill_payer_account_name, cost_category, discount, discount_bundled_discount, discount_total_discount, identity_line_item_id, identity_time_interval, line_item_availability_zone, line_item_blended_cost, line_item_blended_rate, line_item_currency_code, line_item_iam_principal, line_item_legal_entity, line_item_line_item_description, line_item_line_item_type, line_item_net_unblended_cost, line_item_net_unblended_rate, line_item_normalization_factor, line_item_normalized_usage_amount, line_item_operation, line_item_product_code, line_item_resource_id, line_item_tax_type, line_item_unblended_cost, line_item_unblended_rate, line_item_usage_account_id, line_item_usage_account_name, line_item_usage_amount, line_item_usage_end_date, line_item_usage_start_date, line_item_usage_type, pricing_currency, pricing_lease_contract_length, pricing_offering_class, pricing_public_on_demand_cost, pricing_public_on_demand_rate, pricing_purchase_option, pricing_rate_code, pricing_rate_id, pricing_term, pricing_unit, product, product_comment, product_fee_code, product_fee_description, product_from_location, product_from_location_type, product_from_region_code, product_instance_family, product_instance_type, product_instancesku, product_location, product_location_type, product_operation, product_pricing_unit, product_product_family, product_region_code, product_servicecode, product_sku, product_to_location, product_to_location_type, product_to_region_code, product_usagetype, reservation_amortized_upfront_cost_for_usage, reservation_amortized_upfront_fee_for_billing_period, reservation_availability_zone, reservation_effective_cost, reservation_end_time, reservation_modification_status, reservation_net_amortized_upfront_cost_for_usage, reservation_net_amortized_upfront_fee_for_billing_period, reservation_net_effective_cost, reservation_net_recurring_fee_for_usage, reservation_net_unused_amortized_upfront_fee_for_billing_period, reservation_net_unused_recurring_fee, reservation_net_upfront_value, reservation_normalized_units_per_reservation, reservation_number_of_reservations, reservation_recurring_fee_for_usage, reservation_reservation_a_r_n, reservation_start_time, reservation_subscription_id, reservation_total_reserved_normalized_units, reservation_total_reserved_units, reservation_units_per_reservation, reservation_unused_amortized_upfront_fee_for_billing_period, reservation_unused_normalized_unit_quantity, reservation_unused_quantity, reservation_unused_recurring_fee, reservation_upfront_value, resource_tags, savings_plan_amortized_upfront_commitment_for_billing_period, savings_plan_end_time, savings_plan_instance_type_family, savings_plan_net_amortized_upfront_commitment_for_billing_period, savings_plan_net_recurring_commitment_for_billing_period, savings_plan_net_savings_plan_effective_cost, savings_plan_offering_type, savings_plan_payment_option, savings_plan_purchase_term, savings_plan_recurring_commitment_for_billing_period, savings_plan_region, savings_plan_savings_plan_a_r_n, savings_plan_savings_plan_effective_cost, savings_plan_savings_plan_rate, savings_plan_start_time, savings_plan_total_commitment_to_date, savings_plan_used_commitment, tags FROM COST_AND_USAGE_REPORT"
      table_configurations = {
        COST_AND_USAGE_REPORT = {
          BILLING_VIEW_ARN                      = "arn:${data.aws_partition.current.partition}:billing::${local.account_id}:billingview/primary"
          TIME_GRANULARITY                      = var.cur_report_time_unit
          INCLUDE_RESOURCES                     = "TRUE"
          INCLUDE_SPLIT_COST_ALLOCATION_DATA    = "FALSE"
          INCLUDE_CAPACITY_RESERVATION_DATA     = "FALSE"
          INCLUDE_IAM_PRINCIPAL_DATA            = "TRUE"
          INCLUDE_MANUAL_DISCOUNT_COMPATIBILITY = "FALSE"
        }
      }
    }

    destination_configurations {
      s3_destination {
        s3_bucket = local.cur_bucket_id
        s3_prefix = local.cur_report_s3_prefix
        s3_region = var.cur_bucket_region

        s3_output_configurations {
          output_type = "CUSTOM"
          format      = "TEXT_OR_CSV"
          compression = "GZIP"
          overwrite   = "OVERWRITE_REPORT"
        }
      }
    }

    refresh_cadence {
      frequency = "SYNCHRONOUS"
    }
  }

  depends_on = [
    aws_s3_bucket_policy.vantage_cost_and_usage_reports,
    aws_s3_bucket_policy.existing_cur_bucket,
  ]
}

resource "aws_s3_bucket" "vantage_cost_and_usage_reports" {
  count         = local.create_cur_bucket ? 1 : 0
  bucket        = var.cur_bucket_name
  force_destroy = true

  tags = var.tags
}

resource "aws_s3_bucket_acl" "vantage_cost_and_usage_reports" {
  count  = local.create_cur_bucket && var.compatibility_private_bucket_acl ? 1 : 0
  bucket = local.cur_bucket_id
  acl    = "private"
}

resource "aws_s3_bucket_lifecycle_configuration" "vantage_cost_and_usage_reports" {
  count  = local.create_cur_bucket && length(local.cur_bucket_lifecycle_rules) > 0 ? 1 : 0
  bucket = local.cur_bucket_id

  dynamic "rule" {
    for_each = local.cur_bucket_lifecycle_rules

    content {
      id     = rule.value.id
      status = coalesce(rule.value.enabled, true) ? "Enabled" : "Disabled"

      filter {
        prefix = rule.value.prefix != null ? rule.value.prefix : ""
      }

      dynamic "expiration" {
        for_each = try(rule.value.expiration_days, null) != null ? [rule.value.expiration_days] : []

        content {
          days = expiration.value
        }
      }

      dynamic "transition" {
        for_each = try(rule.value.transitions, [])

        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }
    }
  }
}

resource "aws_s3_bucket_public_access_block" "vantage_cost_and_usage_reports" {
  count                   = local.create_cur_bucket ? 1 : 0
  bucket                  = local.cur_bucket_id
  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true
  ignore_public_acls      = true
}

resource "aws_s3_bucket_policy" "vantage_cost_and_usage_reports" {
  count  = local.create_cur_bucket ? 1 : 0
  bucket = aws_s3_bucket.vantage_cost_and_usage_reports[0].id
  policy = data.aws_iam_policy_document.vantage_cur_access[0].json
  depends_on = [
    aws_s3_bucket_public_access_block.vantage_cost_and_usage_reports
  ]
}

resource "aws_s3_bucket_notification" "vantage_cost_and_usage_reports" {
  count  = local.create_cur_bucket ? 1 : 0
  bucket = aws_s3_bucket.vantage_cost_and_usage_reports[0].id
  topic {
    topic_arn     = local.vantage_sns_topic_arn
    events        = ["s3:ObjectCreated:*"]
    filter_suffix = ".csv.gz"
  }
  depends_on = [
    aws_s3_bucket.vantage_cost_and_usage_reports
  ]
}

resource "aws_s3_bucket_notification" "existing_cur_bucket" {
  count       = local.manage_existing_cur_bucket_notification ? 1 : 0
  bucket      = data.aws_s3_bucket.existing_cur_bucket[0].id
  eventbridge = var.existing_cur_bucket_notification_eventbridge

  topic {
    topic_arn     = local.vantage_sns_topic_arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = local.existing_cur_object_prefix != "" ? "${local.existing_cur_object_prefix}/" : null
    filter_suffix = ".csv.gz"
  }

  dynamic "topic" {
    for_each = local.additional_cur_notification_topics

    content {
      id            = topic.value.id
      topic_arn     = topic.value.topic_arn
      events        = topic.value.events
      filter_prefix = topic.value.filter_prefix
      filter_suffix = topic.value.filter_suffix
    }
  }

  dynamic "queue" {
    for_each = local.additional_cur_notification_queues

    content {
      id            = queue.value.id
      queue_arn     = queue.value.queue_arn
      events        = queue.value.events
      filter_prefix = queue.value.filter_prefix
      filter_suffix = queue.value.filter_suffix
    }
  }

  dynamic "lambda_function" {
    for_each = local.additional_cur_notification_lambdas

    content {
      id                  = lambda_function.value.id
      lambda_function_arn = lambda_function.value.lambda_function_arn
      events              = lambda_function.value.events
      filter_prefix       = lambda_function.value.filter_prefix
      filter_suffix       = lambda_function.value.filter_suffix
    }
  }
}

data "aws_iam_policy_document" "vantage_cur_retrieval" {
  count = local.cur_bucket_enabled ? 1 : 0
  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectAcl"
    ]

    resources = [
      local.cur_object_arn
    ]
  }

  dynamic "statement" {
    for_each = local.use_existing_cur_bucket && var.existing_cur_bucket_kms_key_arn != null ? [var.existing_cur_bucket_kms_key_arn] : []

    content {
      effect = "Allow"
      actions = [
        "kms:Decrypt"
      ]
      resources = [statement.value]
    }
  }
}

data "aws_iam_policy_document" "vantage_cur_access" {
  count = local.create_cur_bucket ? 1 : 0

  # Legacy CUR reports
  statement {
    sid    = "S3BucketPermissionsRetrieval"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }
    actions = [
      "s3:GetBucketAcl",
      "s3:GetBucketPolicy",
    ]
    resources = [aws_s3_bucket.vantage_cost_and_usage_reports[0].arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cur:us-east-1:${local.account_id}:definition/*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "S3PutObject"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.vantage_cost_and_usage_reports[0].arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cur:us-east-1:${local.account_id}:definition/*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  # CUR 2.0 reports
  statement {
    sid    = "EnableAWSDataExportsToWriteToS3AndCheckPolicy"
    effect = "Allow"

    principals {
      type = "Service"
      identifiers = [
        "bcm-data-exports.amazonaws.com",
        "billingreports.amazonaws.com"
      ]
    }
    actions = [
      "s3:PutObject",
      "s3:GetBucketPolicy"
    ]

    resources = [
      aws_s3_bucket.vantage_cost_and_usage_reports[0].arn,
      "${aws_s3_bucket.vantage_cost_and_usage_reports[0].arn}/*"
    ]
    condition {
      test     = "StringLike"
      variable = "aws:SourceArn"
      values = [
        "arn:aws:cur:us-east-1:${local.account_id}:definition/*",
        "arn:aws:bcm-data-exports:us-east-1:${local.account_id}:export/*"
      ]
    }
    condition {
      test     = "StringLike"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid    = "VantageCrossAccountRoleRead"
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

  dynamic "statement" {
    for_each = local.enforce_https_only ? [1] : []

    content {
      sid    = "AllowSSLRequestsOnly"
      effect = "Deny"

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      actions = ["s3:*"]

      resources = [
        aws_s3_bucket.vantage_cost_and_usage_reports[0].arn,
        "${aws_s3_bucket.vantage_cost_and_usage_reports[0].arn}/*",
      ]

      condition {
        test     = "Bool"
        variable = "aws:SecureTransport"
        values   = ["false"]
      }

      condition {
        test     = "BoolIfExists"
        variable = "aws:PrincipalIsAWSService"
        values   = ["false"]
      }
    }
  }
}

data "aws_iam_policy_document" "existing_cur_bucket" {
  count = local.manage_existing_cur_bucket_policy ? 1 : 0

  # Kept statements are merged in. Vantage statement blocks override the same Sid.
  source_policy_documents = var.existing_cur_bucket_policy_json != null ? [var.existing_cur_bucket_policy_json] : []

  dynamic "statement" {
    for_each = local.include_cur_billing_policy_statements ? [1] : []

    content {
      sid    = "S3BucketPermissionsRetrieval"
      effect = "Allow"
      principals {
        type        = "Service"
        identifiers = ["billingreports.amazonaws.com"]
      }
      actions = [
        "s3:GetBucketAcl",
        "s3:GetBucketPolicy",
      ]
      resources = [local.cur_bucket_arn]
      condition {
        test     = "StringEquals"
        variable = "aws:SourceArn"
        values   = ["arn:aws:cur:us-east-1:${local.account_id}:definition/*"]
      }
      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }
    }
  }

  dynamic "statement" {
    for_each = local.include_cur_billing_policy_statements ? [1] : []

    content {
      sid       = "S3PutObject"
      effect    = "Allow"
      actions   = ["s3:PutObject"]
      resources = ["${local.cur_bucket_arn}/*"]
      principals {
        type        = "Service"
        identifiers = ["billingreports.amazonaws.com"]
      }
      condition {
        test     = "StringEquals"
        variable = "aws:SourceArn"
        values   = ["arn:aws:cur:us-east-1:${local.account_id}:definition/*"]
      }
      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }
    }
  }

  dynamic "statement" {
    for_each = local.include_cur_billing_policy_statements ? [1] : []

    content {
      sid    = "EnableAWSDataExportsToWriteToS3AndCheckPolicy"
      effect = "Allow"

      principals {
        type = "Service"
        identifiers = [
          "bcm-data-exports.amazonaws.com",
          "billingreports.amazonaws.com"
        ]
      }
      actions = [
        "s3:PutObject",
        "s3:GetBucketPolicy"
      ]

      resources = [
        local.cur_bucket_arn,
        "${local.cur_bucket_arn}/*"
      ]
      condition {
        test     = "StringLike"
        variable = "aws:SourceArn"
        values = [
          "arn:aws:cur:us-east-1:${local.account_id}:definition/*",
          "arn:aws:bcm-data-exports:us-east-1:${local.account_id}:export/*"
        ]
      }
      condition {
        test     = "StringLike"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }
    }
  }

  statement {
    sid    = "VantageCrossAccountRoleRead"
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
      local.cur_object_arn
    ]
  }

  dynamic "statement" {
    for_each = local.enforce_https_only ? [1] : []

    content {
      sid    = "AllowSSLRequestsOnly"
      effect = "Deny"

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      actions = ["s3:*"]

      resources = [
        local.cur_bucket_arn,
        "${local.cur_bucket_arn}/*",
      ]

      condition {
        test     = "Bool"
        variable = "aws:SecureTransport"
        values   = ["false"]
      }

      condition {
        test     = "BoolIfExists"
        variable = "aws:PrincipalIsAWSService"
        values   = ["false"]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "existing_cur_bucket" {
  count  = local.manage_existing_cur_bucket_policy ? 1 : 0
  bucket = data.aws_s3_bucket.existing_cur_bucket[0].id
  policy = data.aws_iam_policy_document.existing_cur_bucket[0].json
}

resource "vantage_aws_provider" "with_bucket" {
  count = local.cur_bucket_enabled ? 1 : 0

  cross_account_arn = aws_iam_role.vantage_cross_account_connection_with_bucket[0].arn
  bucket_arn        = local.cur_bucket_arn
}

resource "vantage_aws_provider" "without_bucket" {
  count = local.cur_bucket_enabled ? 0 : 1

  cross_account_arn = aws_iam_role.vantage_cross_account_connection_without_bucket[0].arn
}
