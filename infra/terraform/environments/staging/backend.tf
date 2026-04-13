# =============================================================================
# Staging — Remote State Backend
# =============================================================================

terraform {
  backend "s3" {
    bucket         = "gitops-platform-tfstate"
    key            = "staging/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "gitops-platform-tfstate-lock"
    encrypt        = true
  }
}
