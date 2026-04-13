# =============================================================================
# ECR Module
# =============================================================================
# Container registry with image scanning and lifecycle policies.
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }
}

# -----------------------------------------------------------------------------
# ECR Repository
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  for_each = toset(var.repository_names)

  name                 = "${var.project_name}-${each.value}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    Name      = "${var.project_name}-${each.value}"
    Component = "ecr"
  })
}

# -----------------------------------------------------------------------------
# Lifecycle Policy — keep last 30 tagged images, remove untagged after 1 day
# -----------------------------------------------------------------------------

resource "aws_ecr_lifecycle_policy" "app" {
  for_each = toset(var.repository_names)

  repository = aws_ecr_repository.app[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep only last ${var.max_image_count} tagged images"
        selection = {
          tagStatus   = "tagged"
          tagPrefixList = ["v", "sha-"]
          countType   = "imageCountMoreThan"
          countNumber = var.max_image_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Repository Policy — allow cross-account pulls (if needed)
# -----------------------------------------------------------------------------

resource "aws_ecr_repository_policy" "app" {
  for_each = var.allow_pull_account_ids != null ? toset(var.repository_names) : toset([])

  repository = aws_ecr_repository.app[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCrossAccountPull"
        Effect = "Allow"
        Principal = {
          AWS = [for id in var.allow_pull_account_ids : "arn:aws:iam::${id}:root"]
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "repository_names" {
  description = "List of application repository names to create"
  type        = list(string)
  default     = ["my-app"]
}

variable "max_image_count" {
  description = "Maximum number of tagged images to retain"
  type        = number
  default     = 30
}

variable "force_delete" {
  description = "Allow force delete of repositories with images"
  type        = bool
  default     = false
}

variable "allow_pull_account_ids" {
  description = "AWS account IDs allowed to pull images (for cross-account)"
  type        = list(string)
  default     = null
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "repository_urls" {
  description = "Map of repository names to their URLs"
  value       = { for k, v in aws_ecr_repository.app : k => v.repository_url }
}

output "repository_arns" {
  description = "Map of repository names to their ARNs"
  value       = { for k, v in aws_ecr_repository.app : k => v.arn }
}

output "registry_id" {
  description = "The registry ID (AWS account ID)"
  value       = values(aws_ecr_repository.app)[0].registry_id
}
