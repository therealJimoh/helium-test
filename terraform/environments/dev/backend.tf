# Partial config: bucket and region come from backend.hcl via `terraform init -backend-config=backend.hcl`.
terraform {
  backend "s3" {
    key          = "helium-test/dev/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
