variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-2"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "service_name" {
  description = "Service name."
  type        = string
  default     = "helium-test"
}

variable "github_repository" {
  description = "GitHub repository."
  type        = string
}

variable "create_oidc_provider" {
  description = "GitHub OIDC provider."
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "Existing GitHub OIDC provider ARN."
  type        = string
  default     = null
}

variable "max_tagged_images" {
  description = "Maximum tagged images."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Default tags."
  type        = map(string)
  default = {
    owner      = "platform"
    managed-by = "terraform"
  }
}
