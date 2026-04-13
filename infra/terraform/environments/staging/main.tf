# =============================================================================
# Staging Environment — Main Configuration
# =============================================================================
# Calls all modules with staging-specific parameters.
# Cost-optimized: single NAT, smaller instances, no Multi-AZ RDS.
# =============================================================================

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "staging"
      ManagedBy   = "terraform"
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "project_name" {
  type    = string
  default = "gitops-platform"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------

module "vpc" {
  source = "../../modules/vpc"

  project_name = var.project_name
  environment  = "staging"
  region       = var.region

  cidr_block           = "10.0.0.0/16"
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  # Cost optimization: single NAT for staging
  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  # Enable VPC endpoints to reduce NAT costs
  enable_vpc_endpoints = true
  enable_flow_logs     = false # Save costs in staging
}

# -----------------------------------------------------------------------------
# EKS
# -----------------------------------------------------------------------------

module "eks" {
  source = "../../modules/eks"

  project_name       = var.project_name
  environment        = "staging"
  cluster_version    = "1.29"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  cluster_endpoint_public_access = true

  # Smaller nodes for staging
  node_instance_types = ["t3.medium"]
  node_min_size       = 2
  node_max_size       = 5
  node_desired_size   = 2

  # Spot instances available but starting at 0
  spot_instance_types = ["t3.medium", "t3a.medium"]
  spot_max_size       = 3

  github_org  = "org"
  github_repo = "gitops-platform"
}

# -----------------------------------------------------------------------------
# RDS
# -----------------------------------------------------------------------------

module "rds" {
  source = "../../modules/rds"

  project_name               = var.project_name
  environment                = "staging"
  vpc_id                     = module.vpc.vpc_id
  private_subnet_ids         = module.vpc.private_subnet_ids
  eks_node_security_group_id = module.eks.node_security_group_id

  instance_class = "db.t3.medium"
  multi_az       = false # Cost saving for staging
}

# -----------------------------------------------------------------------------
# ECR (shared across environments)
# -----------------------------------------------------------------------------

module "ecr" {
  source = "../../modules/ecr"

  project_name     = var.project_name
  repository_names = ["my-app"]
  max_image_count  = 30
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "cluster_autoscaler_role_arn" {
  value = module.eks.cluster_autoscaler_role_arn
}

output "lb_controller_role_arn" {
  value = module.eks.lb_controller_role_arn
}
