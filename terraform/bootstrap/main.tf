module "state_bucket" {
  source = "../modules/state-bucket"

  bucket_name = var.state_bucket_name
}
