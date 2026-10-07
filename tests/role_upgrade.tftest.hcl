# Upgrade tests for moved.tf: prior state at *_with_bucket / *_without_bucket
# must land on the unified addresses without recreating the IAM role.
# Requires Terraform 1.9 or newer.

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

run "legacy_without_bucket" {
  command   = apply
  state_key = "upgrade_without_bucket"

  module {
    source = "./tests/fixtures/legacy_without_bucket"
  }

  override_resource {
    target = aws_iam_role.vantage_cross_account_connection_without_bucket[0]
    values = {
      id = "test-legacy-without-bucket-role-id"
    }
  }

  override_resource {
    target = vantage_aws_provider.without_bucket[0]
    values = {
      id = 9001
    }
  }
}

run "upgrade_without_bucket" {
  command   = apply
  state_key = "upgrade_without_bucket"

  variables {
    enable_autopilot = true
    additional_inline_policies = [
      {
        name   = "extra"
        policy = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
      }
    ]
  }

  assert {
    condition     = aws_iam_role.vantage_cross_account_connection.id == run.legacy_without_bucket.role_id
    error_message = "Member-account upgrade should move the IAM role in state, not recreate it."
  }

  assert {
    condition     = aws_iam_role.vantage_cross_account_connection.id == "test-legacy-without-bucket-role-id"
    error_message = "Member-account upgrade should keep the legacy role id after moved.tf remapping."
  }

  assert {
    condition     = vantage_aws_provider.this.id == run.legacy_without_bucket.provider_id
    error_message = "Member-account upgrade should move vantage_aws_provider in state, not recreate it."
  }

  assert {
    condition     = aws_iam_role_policy.vantage_root.name == "root" && aws_iam_role_policy.vantage_autopilot[0].name == "VantageAutoPilot" && aws_iam_role_policy.additional_inline_policies["extra"].name == "extra"
    error_message = "Member-account upgrade should expose the unified policy addresses."
  }
}

run "legacy_with_bucket" {
  command   = apply
  state_key = "upgrade_with_bucket"

  module {
    source = "./tests/fixtures/legacy_with_bucket"
  }

  override_resource {
    target = aws_iam_role.vantage_cross_account_connection_with_bucket[0]
    values = {
      id = "test-legacy-with-bucket-role-id"
    }
  }

  override_resource {
    target = vantage_aws_provider.with_bucket[0]
    values = {
      id = 9002
    }
  }
}

run "upgrade_with_bucket" {
  command   = apply
  state_key = "upgrade_with_bucket"

  variables {
    cur_bucket_name  = "created-cur-bucket"
    enable_autopilot = true
    additional_inline_policies = [
      {
        name   = "extra"
        policy = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
      }
    ]
  }

  assert {
    condition     = aws_iam_role.vantage_cross_account_connection.id == run.legacy_with_bucket.role_id
    error_message = "CUR-bucket upgrade should move the IAM role in state, not recreate it."
  }

  assert {
    condition     = aws_iam_role.vantage_cross_account_connection.id == "test-legacy-with-bucket-role-id"
    error_message = "CUR-bucket upgrade should keep the legacy role id after moved.tf remapping."
  }

  assert {
    condition     = vantage_aws_provider.this.id == run.legacy_with_bucket.provider_id
    error_message = "CUR-bucket upgrade should move vantage_aws_provider in state, not recreate it."
  }

  assert {
    condition     = aws_s3_bucket.vantage_cost_and_usage_reports[0].id == run.legacy_with_bucket.bucket_id
    error_message = "CUR-bucket upgrade should keep the existing CUR bucket object in state."
  }
}
