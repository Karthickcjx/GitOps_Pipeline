# =============================================================================
# Production — Remote State Backend
# =============================================================================

terraform {
  backend "s3" {
    bucket         = "gitops-platform-tfstate"
    key            = "production/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "gitops-platform-tfstate-lock"
    encrypt        = true
  }
}
