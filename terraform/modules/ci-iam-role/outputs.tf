output "role_arn" {
  description = "CI IAM role ARN."
  value       = aws_iam_role.ci.arn
}

output "role_name" {
  description = "CI IAM role name."
  value       = aws_iam_role.ci.name
}

output "oidc_provider_arn" {
  description = "GitHub OIDC provider ARN."
  value       = local.oidc_provider_arn
}
