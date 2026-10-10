terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.80, < 7.0"
    }
  }
  # Starts on local state (chicken-and-egg); migrate into the bucket afterwards, see README.
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = var.tags
  }
}
