module "ecr" {
  source = "../../modules/ecr"

  name              = var.service_name
  max_tagged_images = var.max_tagged_images
}

module "ci_role" {
  source = "../../modules/ci-iam-role"

  role_name                  = "${var.service_name}-${var.environment}-github-ci"
  github_repository          = var.github_repository
  create_oidc_provider       = var.create_oidc_provider
  existing_oidc_provider_arn = var.existing_oidc_provider_arn
  ecr_repository_arns        = [module.ecr.repository_arn]
}
