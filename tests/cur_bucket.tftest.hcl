# Mocked-provider tests for CUR bucket behavior.
# Requires Terraform 1.7 or newer. Not run in CI.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_s3_bucket" {
    defaults = {
      id                          = "existing-cur-bucket"
      bucket                      = "existing-cur-bucket"
      arn                         = "arn:aws:s3:::existing-cur-bucket"
      region                      = "us-east-1"
      bucket_region               = "us-east-1"
      bucket_regional_domain_name = "existing-cur-bucket.s3.us-east-1.amazonaws.com"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/vantage_cross_account_connection"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      id     = "created-cur-bucket"
      bucket = "created-cur-bucket"
      arn    = "arn:aws:s3:::created-cur-bucket"
    }
  }
}

mock_provider "vantage" {
  mock_data "vantage_aws_provider_info" {
    defaults = {
      iam_role_arn                = "arn:aws:iam::630399649041:role/vantage"
      external_id                 = "external-id"
      root_policy                 = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
      autopilot_policy            = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
      cloudwatch_metrics_policy   = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
      additional_resources_policy = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

run "member_account" {
  command = apply

  assert {
    condition     = length(aws_s3_bucket.vantage_cost_and_usage_reports) == 0 && length(data.aws_s3_bucket.existing_cur_bucket) == 0
    error_message = "A member account should not create or look up a CUR bucket."
  }

  assert {
    condition     = length(aws_iam_role.vantage_cross_account_connection_without_bucket) == 1 && length(vantage_aws_provider.without_bucket) == 1
    error_message = "A member account should get the cross-account role and integration without a bucket."
  }

  assert {
    condition     = length(aws_cur_report_definition.vantage_cost_and_usage_reports) == 0 && length(aws_bcmdataexports_export.vantage_cost_and_usage_reports) == 0 && length(aws_s3_bucket_policy.vantage_cost_and_usage_reports) == 0 && length(aws_s3_bucket_notification.vantage_cost_and_usage_reports) == 0
    error_message = "A member account should not manage a report, bucket policy, or notification."
  }
}

run "created_bucket" {
  command = apply

  variables {
    cur_bucket_name = "created-cur-bucket"
  }

  assert {
    condition     = length(aws_s3_bucket.vantage_cost_and_usage_reports) == 1 && length(aws_s3_bucket_public_access_block.vantage_cost_and_usage_reports) == 1 && length(aws_s3_bucket_lifecycle_configuration.vantage_cost_and_usage_reports) == 1 && length(aws_s3_bucket_acl.vantage_cost_and_usage_reports) == 0
    error_message = "The module should create the CUR bucket, public access block, and lifecycle configuration."
  }

  assert {
    condition     = length(data.aws_s3_bucket.existing_cur_bucket) == 0 && length(aws_s3_bucket_policy.existing_cur_bucket) == 0 && length(aws_s3_bucket_notification.existing_cur_bucket) == 0
    error_message = "A module-created bucket should not use the existing-bucket resources."
  }

  assert {
    condition     = aws_s3_bucket_policy.vantage_cost_and_usage_reports[0].bucket == "created-cur-bucket" && aws_s3_bucket_notification.vantage_cost_and_usage_reports[0].bucket == "created-cur-bucket" && aws_s3_bucket_notification.vantage_cost_and_usage_reports[0].topic[0].filter_suffix == ".csv.gz"
    error_message = "The created bucket should keep its policy and .csv.gz notification."
  }

  assert {
    condition     = aws_cur_report_definition.vantage_cost_and_usage_reports[0].s3_prefix == "daily-v1" && aws_cur_report_definition.vantage_cost_and_usage_reports[0].s3_bucket == "created-cur-bucket"
    error_message = "The managed report should keep the daily-v1 prefix on the created bucket."
  }

  assert {
    condition = contains([
      for statement in data.aws_iam_policy_document.vantage_cur_access[0].statement : statement.sid
    ], "VantageCrossAccountRoleRead")
    error_message = "The cross-account read statement should have a statement ID."
  }

  assert {
    condition     = vantage_aws_provider.with_bucket[0].bucket_arn == "arn:aws:s3:::created-cur-bucket"
    error_message = "The integration should reference the created bucket."
  }
}

run "existing_bucket_with_report" {
  command = apply

  variables {
    existing_cur_bucket_name = "existing-cur-bucket"
  }

  assert {
    condition     = length(aws_s3_bucket.vantage_cost_and_usage_reports) == 0 && length(aws_s3_bucket_public_access_block.vantage_cost_and_usage_reports) == 0 && length(aws_s3_bucket_lifecycle_configuration.vantage_cost_and_usage_reports) == 0 && length(aws_s3_bucket_acl.vantage_cost_and_usage_reports) == 0
    error_message = "An existing bucket should not be created or have its lifecycle, ACL, or public access block changed."
  }

  assert {
    condition     = length(aws_cur_report_definition.vantage_cost_and_usage_reports) == 1 && aws_cur_report_definition.vantage_cost_and_usage_reports[0].s3_bucket == "existing-cur-bucket" && aws_cur_report_definition.vantage_cost_and_usage_reports[0].s3_prefix == "daily-v1"
    error_message = "The module should create the CUR report on the existing bucket at daily-v1."
  }

  assert {
    condition     = length(aws_s3_bucket_policy.existing_cur_bucket) == 1 && aws_s3_bucket_policy.existing_cur_bucket[0].bucket == "existing-cur-bucket"
    error_message = "Creating the report should manage the existing bucket policy."
  }

  assert {
    condition = contains([
      for statement in data.aws_iam_policy_document.existing_cur_bucket[0].statement : statement.sid
      ], "S3PutObject") && !contains([
      for statement in data.aws_iam_policy_document.existing_cur_bucket[0].statement : statement.sid
    ], "AllowSSLRequestsOnly")
    error_message = "The managed policy should let billing write and should not deny plain HTTP by default."
  }

  assert {
    condition     = aws_s3_bucket_notification.existing_cur_bucket[0].topic[0].filter_prefix == "daily-v1/" && aws_s3_bucket_notification.existing_cur_bucket[0].eventbridge == false
    error_message = "The Vantage notification should be limited to the report prefix and should turn EventBridge off."
  }

  assert {
    condition = contains(flatten([
      for statement in data.aws_iam_policy_document.vantage_cur_retrieval[0].statement : statement.resources
    ]), "arn:aws:s3:::existing-cur-bucket/daily-v1/*")
    error_message = "The role's GetObject access should be limited to the report prefix."
  }

  assert {
    condition     = vantage_aws_provider.with_bucket[0].bucket_arn == "arn:aws:s3:::existing-cur-bucket" && output.vantage_cost_and_usage_reports_bucket_id == "existing-cur-bucket"
    error_message = "The integration and bucket output should reference the existing bucket."
  }
}

run "self_managed_report_with_prefix" {
  command = apply

  variables {
    existing_cur_bucket_name = "existing-cur-bucket"
    cur_report_enabled       = false
    cur_report_s3_prefix     = "cur/vantage"
  }

  assert {
    condition     = length(aws_cur_report_definition.vantage_cost_and_usage_reports) == 0 && length(aws_bcmdataexports_export.vantage_cost_and_usage_reports) == 0 && length(aws_s3_bucket_policy.existing_cur_bucket) == 0
    error_message = "A self-managed report should not create a report or replace the bucket policy."
  }

  assert {
    condition     = aws_s3_bucket_notification.existing_cur_bucket[0].topic[0].filter_prefix == "cur/vantage/"
    error_message = "The notification filter should use the configured prefix."
  }

  assert {
    condition = contains(flatten([
      for statement in data.aws_iam_policy_document.vantage_cur_retrieval[0].statement : statement.resources
    ]), "arn:aws:s3:::existing-cur-bucket/cur/vantage/*")
    error_message = "The role's GetObject access should be limited to the configured prefix."
  }
}

run "self_managed_report_without_prefix" {
  command = apply

  variables {
    existing_cur_bucket_name = "existing-cur-bucket"
    cur_report_enabled       = false
  }

  assert {
    condition     = length(aws_s3_bucket_policy.existing_cur_bucket) == 0 && aws_s3_bucket_notification.existing_cur_bucket[0].topic[0].filter_prefix == null
    error_message = "Without a prefix, the policy stays unchanged and the notification covers the whole bucket."
  }

  assert {
    condition = contains(flatten([
      for statement in data.aws_iam_policy_document.vantage_cur_retrieval[0].statement : statement.resources
    ]), "arn:aws:s3:::existing-cur-bucket/*")
    error_message = "Without a prefix, GetObject access should cover the whole bucket."
  }
}

run "force_policy_and_https" {
  command = apply

  variables {
    existing_cur_bucket_name          = "existing-cur-bucket"
    cur_report_enabled                = false
    existing_cur_bucket_manage_policy = true
    enforce_https_only                = true
  }

  assert {
    condition     = length(aws_s3_bucket_policy.existing_cur_bucket) == 1
    error_message = "existing_cur_bucket_manage_policy should force the bucket policy on."
  }

  assert {
    condition = contains([
      for statement in data.aws_iam_policy_document.existing_cur_bucket[0].statement : statement.sid
      ], "AllowSSLRequestsOnly") && contains([
      for statement in data.aws_iam_policy_document.existing_cur_bucket[0].statement : statement.sid
      ], "VantageCrossAccountRoleRead") && !contains([
      for statement in data.aws_iam_policy_document.existing_cur_bucket[0].statement : statement.sid
    ], "S3PutObject")
    error_message = "A forced policy without a module-created report should be the cross-account read statement plus the HTTPS deny, not the billing write statements."
  }
}

run "keep_policy_statements" {
  command = apply

  variables {
    existing_cur_bucket_name = "existing-cur-bucket"
    existing_cur_bucket_policy_json = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "KeepMe"
          Effect    = "Allow"
          Principal = { AWS = "arn:aws:iam::123456789012:root" }
          Action    = "s3:ListBucket"
          Resource  = "arn:aws:s3:::existing-cur-bucket"
        },
        {
          Sid       = "VantageCrossAccountRoleRead"
          Effect    = "Allow"
          Principal = "*"
          Action    = "s3:DeleteObject"
          Resource  = "arn:aws:s3:::existing-cur-bucket/*"
        },
        {
          Effect    = "Deny"
          Principal = "*"
          Action    = "s3:DeleteBucket"
          Resource  = "arn:aws:s3:::existing-cur-bucket"
        },
      ]
    })
  }

  assert {
    condition     = data.aws_iam_policy_document.existing_cur_bucket[0].source_policy_documents[0] == var.existing_cur_bucket_policy_json
    error_message = "Statements to keep should be merged into the managed policy."
  }

  assert {
    condition = contains([
      for statement in data.aws_iam_policy_document.existing_cur_bucket[0].statement : statement.sid
    ], "VantageCrossAccountRoleRead")
    error_message = "The Vantage read statement should override a kept statement with the same Sid."
  }
}

run "notifications_and_eventbridge" {
  command = apply

  variables {
    existing_cur_bucket_name                     = "existing-cur-bucket"
    existing_cur_bucket_notification_eventbridge = true
    existing_cur_bucket_additional_notifications = {
      topics = [{
        topic_arn     = "arn:aws:sns:us-east-1:123456789012:other"
        events        = ["s3:ObjectCreated:*"]
        filter_suffix = ".json"
      }]
      queues = [{
        queue_arn = "arn:aws:sqs:us-east-1:123456789012:other"
        events    = ["s3:ObjectRemoved:*"]
      }]
      lambda_functions = [{
        lambda_function_arn = "arn:aws:lambda:us-east-1:123456789012:function:other"
        events              = ["s3:ObjectCreated:*"]
      }]
    }
  }

  assert {
    condition     = aws_s3_bucket_notification.existing_cur_bucket[0].eventbridge == true
    error_message = "EventBridge should stay enabled when requested."
  }

  assert {
    condition     = length(aws_s3_bucket_notification.existing_cur_bucket[0].topic) == 2 && length(aws_s3_bucket_notification.existing_cur_bucket[0].queue) == 1 && length(aws_s3_bucket_notification.existing_cur_bucket[0].lambda_function) == 1
    error_message = "Additional SNS, SQS, and Lambda notifications should be kept next to the Vantage topic."
  }

  assert {
    condition = contains([
      for topic in aws_s3_bucket_notification.existing_cur_bucket[0].topic : topic.topic_arn
      ], "arn:aws:sns:us-east-1:630399649041:cost-and-usage-report-uploaded") && contains([
      for topic in aws_s3_bucket_notification.existing_cur_bucket[0].topic : topic.topic_arn
    ], "arn:aws:sns:us-east-1:123456789012:other")
    error_message = "The managed notification should include the Vantage topic and the kept topic."
  }
}

run "kms_decrypt" {
  command = apply

  variables {
    existing_cur_bucket_name        = "existing-cur-bucket"
    existing_cur_bucket_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    upgrade_to_cur_2                = true
  }

  assert {
    condition     = length(aws_bcmdataexports_export.vantage_cost_and_usage_reports) == 1 && length(aws_cur_report_definition.vantage_cost_and_usage_reports) == 0 && aws_bcmdataexports_export.vantage_cost_and_usage_reports[0].export[0].destination_configurations[0].s3_destination[0].s3_bucket == "existing-cur-bucket"
    error_message = "CUR 2.0 on an existing bucket should target that bucket and not also create a legacy report."
  }

  assert {
    condition = contains(flatten([
      for statement in data.aws_iam_policy_document.vantage_cur_retrieval[0].statement : statement.actions
      ]), "kms:Decrypt") && contains(flatten([
      for statement in data.aws_iam_policy_document.vantage_cur_retrieval[0].statement : statement.resources
    ]), "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000")
    error_message = "The role should be allowed to decrypt with the existing bucket's KMS key."
  }
}

run "opt_out_policy_and_notification" {
  command = apply

  variables {
    existing_cur_bucket_name                = "existing-cur-bucket"
    existing_cur_bucket_manage_policy       = false
    existing_cur_bucket_manage_notification = false
  }

  assert {
    condition     = length(aws_s3_bucket_policy.existing_cur_bucket) == 0 && length(aws_s3_bucket_notification.existing_cur_bucket) == 0 && length(aws_cur_report_definition.vantage_cost_and_usage_reports) == 1
    error_message = "Both opt-outs should skip the policy and notification while still creating the report."
  }

  assert {
    condition     = length(aws_iam_role.vantage_cross_account_connection_with_bucket) == 1 && length(vantage_aws_provider.with_bucket) == 1
    error_message = "Opting out of the policy and notification should still create the role and integration."
  }
}

run "wrong_region" {
  command = plan

  variables {
    existing_cur_bucket_name                = "existing-cur-bucket"
    cur_bucket_region                       = "us-west-2"
    existing_cur_bucket_manage_notification = false
  }

  expect_failures = [
    data.aws_s3_bucket.existing_cur_bucket,
  ]
}

run "both_bucket_variables" {
  command = plan

  variables {
    cur_bucket_name          = "created-cur-bucket"
    existing_cur_bucket_name = "existing-cur-bucket"
  }

  expect_failures = [
    data.aws_caller_identity.current,
  ]
}

run "invalid_prefix" {
  command = plan

  variables {
    existing_cur_bucket_name = "existing-cur-bucket"
    cur_report_s3_prefix     = "not a valid prefix"
  }

  expect_failures = [
    var.cur_report_s3_prefix,
  ]
}
