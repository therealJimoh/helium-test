variable "name" {
  description = "ECR repository name."
  type        = string
}

variable "image_tag_mutability" {
  description = "Image tag mutability."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "untagged_expiry_days" {
  description = "Untagged image expiry in days."
  type        = number
  default     = 7
}

variable "max_tagged_images" {
  description = "Maximum tagged images."
  type        = number
  default     = 30
}

variable "kms_key_arn" {
  description = "KMS key ARN for image encryption."
  type        = string
  default     = null
}

variable "force_delete" {
  description = "Force delete repository."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Resource tags."
  type        = map(string)
  default     = {}
}
