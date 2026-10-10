variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-2"
}

variable "state_bucket_name" {
  description = "Terraform state bucket name."
  type        = string
}

variable "tags" {
  description = "Default tags."
  type        = map(string)
  default = {
    owner      = "platform"
    managed-by = "terraform"
    stack      = "bootstrap"
  }
}
