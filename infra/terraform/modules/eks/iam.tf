# =============================================================================
# EKS Module — IAM Policies
# =============================================================================
# Additional IAM policies and roles for EKS workloads.
# IRSA roles for cluster components are in main.tf.
# This file contains application-specific IRSA roles.
# =============================================================================

# -----------------------------------------------------------------------------
# IRSA: Application Service Account (my-app)
# Read-only access to specific Secrets Manager paths
# -----------------------------------------------------------------------------

module "app_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.37"

  role_name = "${var.project_name}-${var.environment}-app"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["my-app-${var.environment}:my-app"]
    }
  }

  role_policy_arns = {
    app_secrets = aws_iam_policy.app_secrets.arn
  }

  tags = var.tags
}

resource "aws_iam_policy" "app_secrets" {
  name        = "${var.project_name}-${var.environment}-app-secrets"
  description = "Allow app to read specific Secrets Manager secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:*:*:secret:gitops-platform/${var.environment}/my-app/*"
        ]
      }
    ]
  })

  tags = var.tags
}

# -----------------------------------------------------------------------------
# GitHub Actions OIDC Role (for CI/CD)
# Allows GitHub Actions to push to ECR without static credentials
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.environment == "staging" ? 1 : 0 # Create once, shared

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = var.tags
}

resource "aws_iam_role" "github_actions" {
  count = var.environment == "staging" ? 1 : 0

  name = "${var.project_name}-github-actions-ecr"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github[0].arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "github_actions_ecr" {
  count = var.environment == "staging" ? 1 : 0

  name = "${var.project_name}-github-actions-ecr-policy"
  role = aws_iam_role.github_actions[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "arn:aws:ecr:*:${data.aws_caller_identity.current.account_id}:repository/${var.project_name}-*"
      }
    ]
  })
}

# Additional variables for IAM
variable "github_org" {
  description = "GitHub organization name for OIDC trust"
  type        = string
  default     = "org"
}

variable "github_repo" {
  description = "GitHub repository name for OIDC trust"
  type        = string
  default     = "gitops-platform"
}
