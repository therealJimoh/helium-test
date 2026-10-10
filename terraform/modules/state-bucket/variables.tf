variable "bucket_name" {
  description = "Terraform state bucket name."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for state encryption."
  type        = string
  default     = null
}

variable "noncurrent_version_expiry_days" {
  description = "Noncurrent state version expiry in days."
  type        = number
  default     = 90
}

variable "tags" {
  description = "Resource tags."
  type        = map(string)
  default     = {}
}
