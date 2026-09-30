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

  mock_data "aws_s3_bucket" {
    defaults = {
      id     = "existing-cur-bucket"
      arn    = "arn:aws:s3:::existing-cur-bucket"
      region = "us-east-1"
    }
  }

  mock_data "aws_s3_bucket_policy" {
    defaults = {
      policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"CustomerStatement\",\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::123456789012:root\"},\"Action\":\"s3:ListBucket\",\"Resource\":\"arn:aws:s3:::existing-cur-bucket\"}]}"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/vantage_cross_account_connection"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      id  = "created-cur-bucket"
      arn = "arn:aws:s3:::created-cur-bucket"
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

run "member_account_without_bucket" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket.vantage_cost_and_usage_reports) == 0 && length(aws_s3_bucket_policy.vantage_cost_and_usage_reports) == 0 && length(aws_s3_bucket_notification.vantage_cost_and_usage_reports) == 0
    error_message = "No bucket resources should be managed without a CUR bucket."
  }

  assert {
    condition     = length(vantage_aws_provider.without_bucket) == 1
    error_message = "The integration should be created without a bucket."
  }
}

run "module_created_bucket" {
  command = apply

  variables {
    cur_bucket_name = "created-cur-bucket"
  }

  assert {
    condition     = length(aws_s3_bucket.vantage_cost_and_usage_reports) == 1 && length(aws_s3_bucket_public_access_block.vantage_cost_and_usage_reports) == 1 && length(aws_s3_bucket_lifecycle_configuration.vantage_cost_and_usage_reports) == 1
    error_message = "The module should create and configure the CUR bucket."
  }

  assert {
    condition     = aws_s3_bucket_policy.vantage_cost_and_usage_reports[0].bucket == "created-cur-bucket" && aws_s3_bucket_notification.vantage_cost_and_usage_reports[0].bucket == "created-cur-bucket"
    error_message = "The bucket policy and notification should target the created bucket."
  }

  assert {
    condition     = vantage_aws_provider.with_bucket[0].bucket_arn == "arn:aws:s3:::created-cur-bucket"
    error_message = "The integration should reference the created bucket."
  }
}

run "existing_bucket" {
  command = apply

  variables {
    existing_cur_bucket_name = "existing-cur-bucket"
  }

  assert {
    condition     = length(aws_s3_bucket.vantage_cost_and_usage_reports) == 0 && length(aws_s3_bucket_public_access_block.vantage_cost_and_usage_reports) == 0 && length(aws_s3_bucket_lifecycle_configuration.vantage_cost_and_usage_reports) == 0 && length(aws_s3_bucket_acl.vantage_cost_and_usage_reports) == 0
    error_message = "The module should not create or reconfigure an existing bucket."
  }

  assert {
    condition     = aws_s3_bucket_policy.vantage_cost_and_usage_reports[0].bucket == "existing-cur-bucket"
    error_message = "The bucket policy should be applied to the existing bucket."
  }

  assert {
    condition     = length(data.aws_s3_bucket_policy.existing_cur_bucket) == 1
    error_message = "The existing bucket policy should be read so it can be merged."
  }

  assert {
    condition     = aws_s3_bucket_notification.vantage_cost_and_usage_reports[0].bucket == "existing-cur-bucket"
    error_message = "The S3 event notification should be applied to the existing bucket."
  }

  assert {
    condition     = length(aws_cur_report_definition.vantage_cost_and_usage_reports) == 1 && aws_cur_report_definition.vantage_cost_and_usage_reports[0].s3_bucket == "existing-cur-bucket"
    error_message = "The CUR report should deliver to the existing bucket."
  }

  assert {
    condition     = vantage_aws_provider.with_bucket[0].bucket_arn == "arn:aws:s3:::existing-cur-bucket"
    error_message = "The integration should reference the existing bucket."
  }

  assert {
    condition     = output.vantage_cost_and_usage_reports_bucket_id == "existing-cur-bucket"
    error_message = "The bucket ID output should reference the existing bucket."
  }
}

run "existing_bucket_without_a_policy" {
  command = plan

  variables {
    existing_cur_bucket_name       = "existing-cur-bucket"
    existing_cur_bucket_has_policy = false
  }

  assert {
    condition     = length(data.aws_s3_bucket_policy.existing_cur_bucket) == 0 && length(aws_s3_bucket_policy.vantage_cost_and_usage_reports) == 1
    error_message = "A bucket with no policy should get the Vantage policy without reading a current one."
  }
}

run "existing_bucket_without_policy_or_notification" {
  command = plan

  variables {
    existing_cur_bucket_name                = "existing-cur-bucket"
    existing_cur_bucket_manage_policy       = false
    existing_cur_bucket_manage_notification = false
  }

  assert {
    condition     = length(aws_s3_bucket_policy.vantage_cost_and_usage_reports) == 0 && length(aws_s3_bucket_notification.vantage_cost_and_usage_reports) == 0 && length(data.aws_s3_bucket_policy.existing_cur_bucket) == 0
    error_message = "Bucket policy and notification should be skippable for an existing bucket."
  }
}

run "existing_bucket_wrong_region" {
  command = plan

  variables {
    existing_cur_bucket_name = "existing-cur-bucket"
    cur_bucket_region        = "us-west-2"
  }

  expect_failures = [aws_s3_bucket_notification.vantage_cost_and_usage_reports]
}

run "both_bucket_variables_set" {
  command = plan

  variables {
    cur_bucket_name          = "created-cur-bucket"
    existing_cur_bucket_name = "existing-cur-bucket"
  }

  expect_failures = [data.aws_caller_identity.current]
}
