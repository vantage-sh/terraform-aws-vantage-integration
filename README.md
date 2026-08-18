# terraform-vantage-integrations

This module handles linking an AWS account with your Vantage account. For management AWS accounts, use the `cur_bucket_name` variable to provision an Amazon S3 bucket and Cost and Usage Report (CUR) 2.0 data export. Member accounts need cross-account access but do not need their own CUR bucket.

> **Before you begin:** A Vantage API token with **Write** scope, assigned to the **Everyone** team, is required. See [the Vantage documentation](https://docs.vantage.sh/api/authentication) for information on how to create a token. Set the `VANTAGE_API_TOKEN` environment variable (or configure the provider’s `api_token`) before running Terraform.

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
`upgrade_to_cur_2 = true` (the default) replaces `aws_cur_report_definition`
with `aws_bcmdataexports_export`. Set `upgrade_to_cur_2 = false` to continue
managing only the legacy CUR 1.0 report.

When `cur_bucket_name` is set, the bucket policy denies plain-HTTP access by default (`enforce_https_only = true`). AWS billing report delivery is exempt via `aws:PrincipalIsAWSService`. Set `enforce_https_only = false` in the module block to disable the deny statement.

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
