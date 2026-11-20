provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Lifecycle = "persistent"
      Tenant    = "senraj-single-tenant"
    }
  }
}
