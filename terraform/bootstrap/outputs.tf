output "state_bucket_name" {
  description = "Terraform state bucket name."
  value       = module.state_bucket.bucket_name
}

output "state_bucket_arn" {
  description = "Terraform state bucket ARN."
  value       = module.state_bucket.bucket_arn
}
