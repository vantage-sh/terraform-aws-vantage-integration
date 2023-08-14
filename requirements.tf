terraform {
  required_providers {
    vantage = {
      source = "vantage-sh/vantage"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5"
    }
  }
  required_version = ">= 1.0.0"
}