variable "role_name" {
  description = "CI IAM role name."
  type        = string
}

variable "github_repository" {
  description = "GitHub repository."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be in owner/name form."
  }
}

variable "allowed_subjects" {
  description = "Allowed OIDC subject claims."
  type        = list(string)
  default     = ["ref:refs/heads/main"]
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

variable "ecr_repository_arns" {
  description = "ECR repository ARNs."
  type        = list(string)
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds."
  type        = number
  default     = 3600
}

variable "tags" {
  description = "Resource tags."
  type        = map(string)
  default     = {}
}
