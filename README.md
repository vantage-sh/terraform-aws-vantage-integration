# terraform-vantage-integrations

This module handles linking an AWS account with your Vantage account. For root AWS accounts, you will want to provision a CUR bucket via the `cur_bucket_name` variable. For subaccount you will want to link access but won't need to configure the CUR bucket.

## Usage
This module configures an AWS Account integration on Vantage. By default, it does not configure a CUR integration. If the account is your root AWS account and you want to configure a CUR integration, use the `cur_bucket_name` variable to provision that. The bucket name is used for a private S3 bucket and must be globally unique.

The below examples assumes you'll use the [assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#assuming-an-iam-role) feature of the AWS provider to access the desired AWS account.

### Management AWS Account with Cost and Usage Reports (CUR) Integration
This is an example for creating a management (root) AWS account integration where CUR and an S3 bucket are provisioned in addition to the cross account IAM role.

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
  cur_bucket_name = "my-company-cur-vantage"
}
```

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
