output "ecr_repository_url" {
  description = "ECR repository URL."
  value       = module.ecr.repository_url
}

output "ecr_repository_name" {
  description = "ECR repository name."
  value       = module.ecr.repository_name
}

output "ci_role_arn" {
  description = "CI IAM role ARN."
  value       = module.ci_role.role_arn
}
