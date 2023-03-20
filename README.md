# terraform-vantage-integrations

This module handles linking an AWS account with your Vantage account. For root AWS accounts, you will want to provision a CUR bucket via the `cur_bucket_name` variable. For subaccount you will want to link access but won't need to configure the CUR bucket.

## Usage

The base module configures an AWS Account integration on Vantage using the [aws_provider submodule](modules/aws_provider). The submodule itself can be used if additional configuration is required. By default, it does not configure a CUR integration. If the account is your root AWS account and you want to configure a CUR integration, use the `cur_bucket_name` variable to provision that. The bucket name is used for a private S3 bucket and must be globally unique.

The below example assumes you'll use the [assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#assuming-an-iam-role) feature of the AWS provider to access the desired AWS account.

```hcl
provider "aws" {
  region = "us-east-1"
  assume_role {
    role_arn = "arn:aws:iam::123456789012:role/admin-role"
  }
}

module "integrations" {
  source = "vantage-sh/aws/integrations"
}
```
