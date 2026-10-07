# terraform-vantage-integrations

This module handles linking an AWS account with your Vantage account. For management AWS accounts, use the `cur_bucket_name` variable to provision an Amazon S3 bucket and Cost and Usage Report (CUR). Member accounts need cross-account access but do not need their own CUR bucket.

> **Before you begin:** A Vantage API token with **Write** scope, assigned to the **Everyone** team, is required. See [the Vantage documentation](https://docs.vantage.sh/api/authentication) for information on how to create a token. Set the `VANTAGE_API_TOKEN` environment variable (or configure the provider’s `api_token`) before running Terraform. This module requires version 5.48.0 or newer of the HashiCorp AWS provider.

## Usage

This module configures an AWS account integration on Vantage. By default, it does not configure a CUR integration. If the account is your management AWS account and you want to configure a CUR integration, use the `cur_bucket_name` variable. The bucket name is used for a private S3 bucket and must be globally unique.

By default, the bucket is provisioned in the `us-east-1` region. The AWS provider region and `cur_bucket_region` must match so the S3 bucket and Vantage Simple Notification Service (SNS) topic are in the same region.

Vantage supports CUR buckets in the following regions:

- `ap-southeast-1`
- `eu-west-1`
- `eu-west-2`
- `us-east-1`
- `us-west-2`

The below examples assume you'll use the [assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#assuming-an-iam-role) feature of the AWS provider to access the desired AWS account.

### Management AWS Account with CUR 2.0 Integration

This example creates a management AWS account integration with a CUR 2.0 data export, S3 bucket, and cross-account Identity and Access Management (IAM) role. Creating the CUR bucket in your management account is _highly recommended_.

```hcl
provider "aws" {
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::123456789012:role/admin-role"
  }
}

module "vantage-integration" {
  source  = "vantage-sh/vantage-integration/aws"

  # Bucket names must be globally unique. It is provisioned with private acl's
  # and only accessed by Vantage via the provisioned cross account role.
  cur_bucket_name   = "my-company-cur-vantage"
  cur_bucket_region = "us-east-1"
  # Opt in to replacing the legacy CUR 1.0 report with CUR 2.0.
  upgrade_to_cur_2 = true
  # Optional: granularity of the CUR 2.0 data export: "HOURLY" or "DAILY"
  cur_report_time_unit = "HOURLY"
  # Optional: customize CUR bucket lifecycle (default retains the historical
  # remove-old-reports / 200-day expiration behavior via the simple settings).
  # Set to [] to disable lifecycle rules.
  # cur_bucket_lifecycle_rules = [
  #   {
  #     id              = "remove-old-reports"
  #     expiration_days = 200
  #     transitions = [
  #       {
  #         days          = 30
  #         storage_class = "STANDARD_IA"
  #       }
  #     ]
  #   }
  # ]
}
```

#### Self-managed CUR 2.0 Data Export

To create the bucket and Vantage integration without also creating the module's
`aws_bcmdataexports_export`, disable report creation and manage an
`aws_bcmdataexports_export` separately:

```hcl
module "vantage-integration" {
  source = "vantage-sh/vantage-integration/aws"

  cur_bucket_name    = "my-company-cur-vantage"
  cur_bucket_region  = "us-east-1"
  cur_report_enabled = false
}
```

Target the module-managed bucket from the Data Export and configure gzip CSV
output so the existing `.csv.gz` S3 notification delivers report updates to
Vantage.

When upgrading from a module version that managed a legacy CUR 1.0 report,
remove the `cur_report_additional_schema_elements` input and run
`terraform init -upgrade`. The module continues managing the legacy report by
default. Set `upgrade_to_cur_2 = true` to replace `aws_cur_report_definition`
with `aws_bcmdataexports_export`.

When `cur_bucket_name` is set, the bucket policy denies plain-HTTP access by default (`enforce_https_only` defaults to `true` for a bucket this module creates). AWS billing report delivery is exempt via `aws:PrincipalIsAWSService`. Set `enforce_https_only = false` in the module block to disable the deny statement.

### Existing S3 bucket

Use `existing_cur_bucket_name` instead of `cur_bucket_name` when the bucket already exists. The module looks the bucket up with a data source. It does not create or delete the bucket, and it does not change the bucket's lifecycle rules, ACL, or public access block. It manages the CUR report or CUR 2.0 export (unless `cur_report_enabled = false`), the cross-account role, the Vantage integration, and by default the bucket policy and S3 event notification.

The bucket must be in `cur_bucket_region`, and the AWS provider must use that same region. The bucket lookup fails when the bucket is in a different region, whether or not the module manages the notification. Setting both `cur_bucket_name` and `existing_cur_bucket_name` fails at plan time.

```hcl
module "vantage-integration" {
  source = "vantage-sh/vantage-integration/aws"

  existing_cur_bucket_name = "company-cur-bucket"
  cur_bucket_region        = "us-east-1"
  upgrade_to_cur_2         = true
}
```

`cur_report_s3_prefix` defaults to `<time unit>-v1` (for example `daily-v1`), which is the prefix this module has always used. On an existing bucket, the Vantage notification filter and the role's `s3:GetObject` access are limited to that prefix. Set `cur_report_enabled = false` when you already manage the report. If you do that and leave the prefix unset, the notification and `s3:GetObject` access cover the whole bucket.

```hcl
module "vantage-integration" {
  source = "vantage-sh/vantage-integration/aws"

  existing_cur_bucket_name = "company-cur-bucket"
  cur_bucket_region        = "us-east-1"
  cur_report_enabled       = false
  # Optional. Omit to cover the whole bucket.
  cur_report_s3_prefix = "cur/vantage"
}
```

#### Bucket policy

The module replaces the bucket policy, matching the existing-bucket CloudFormation template. It manages that policy by default only when it creates the CUR report, because AWS billing needs the policy to write report files. With `cur_report_enabled = false` the policy is left alone: the Vantage role is in the same account and reads reports through its IAM policy.

Pass statements to keep in `existing_cur_bucket_policy_json`. They are merged into the managed policy, and Vantage statements override statements with the same Sid. Set `existing_cur_bucket_manage_policy` to `true` or `false` to override the default.

`enforce_https_only` defaults to `false` for an existing bucket. The plain-HTTP deny applies to every client of the bucket. Set `enforce_https_only = true` to add it.

For an SSE-KMS bucket, set `existing_cur_bucket_kms_key_arn` so the role is allowed `kms:Decrypt` on that key.

#### S3 event notification

S3 allows one notification configuration per bucket, so the module replaces it with the Vantage topic. Keep other destinations with `existing_cur_bucket_additional_notifications` (SNS topics, SQS queues, and Lambda functions). Set `existing_cur_bucket_notification_eventbridge = true` to keep EventBridge enabled. Otherwise the managed configuration turns EventBridge off. Set `existing_cur_bucket_manage_notification = false` to skip the notification entirely.

#### Limits

- `terraform destroy`, or removing this module, deletes the bucket policy and the notification configuration when the module manages them. That includes statements and notifications passed in to keep. The bucket itself is not deleted.
- An explicit `Deny` in a bucket policy this module does not manage can still block the Vantage role. The role's IAM policy is not enough when the bucket policy denies it.

### Member account

This is an example for creating a member AWS account integration. A cross account IAM role is created for use in gathering cost recommendations, active resources, etc. by Vantage.

```hcl
provider "aws" {
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::123456789012:role/admin-role"
  }
}

module "vantage-integration" {
  source  = "vantage-sh/vantage-integration/aws"
}
```
