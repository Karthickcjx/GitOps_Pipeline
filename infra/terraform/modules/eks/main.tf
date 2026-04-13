# =============================================================================
# EKS Module
# =============================================================================
# Creates an EKS cluster with:
#   - Managed node groups (on-demand + spot)
#   - Cluster add-ons (CoreDNS, kube-proxy, VPC CNI)
#   - AWS Load Balancer Controller
#   - IRSA roles for service accounts
#   - Cluster autoscaler support
# =============================================================================

terraform {
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
  }
}

# -----------------------------------------------------------------------------
# EKS Cluster
# -----------------------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name    = "${var.project_name}-${var.environment}"
  cluster_version = var.cluster_version

  # Networking
  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Cluster endpoint access
  cluster_endpoint_public_access  = var.cluster_endpoint_public_access
  cluster_endpoint_private_access = true

  # Encryption
  cluster_encryption_config = {
    provider_key_arn = var.kms_key_arn
    resources        = ["secrets"]
  }

  # Logging
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Managed node groups
  eks_managed_node_groups = {
    # General-purpose on-demand nodes
    general = {
      name            = "general-ondemand"
      instance_types  = var.node_instance_types
      capacity_type   = "ON_DEMAND"
      min_size        = var.node_min_size
      max_size        = var.node_max_size
      desired_size    = var.node_desired_size

      # Use latest EKS-optimized AMI
      ami_type = "AL2023_x86_64_STANDARD"

      labels = {
        role        = "general"
        environment = var.environment
      }

      tags = {
        "k8s.io/cluster-autoscaler/enabled"                                          = "true"
        "k8s.io/cluster-autoscaler/${var.project_name}-${var.environment}"            = "owned"
      }
    }

    # Spot instances for non-critical workloads (cost optimization)
    spot = {
      name            = "spot-workers"
      instance_types  = var.spot_instance_types
      capacity_type   = "SPOT"
      min_size        = 0
      max_size        = var.spot_max_size
      desired_size    = 0

      ami_type = "AL2023_x86_64_STANDARD"

      labels = {
        role        = "spot"
        environment = var.environment
      }

      taints = [{
        key    = "spot"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]

      tags = {
        "k8s.io/cluster-autoscaler/enabled"                                          = "true"
        "k8s.io/cluster-autoscaler/${var.project_name}-${var.environment}"            = "owned"
      }
    }
  }

  # Cluster add-ons
  cluster_addons = {
    coredns = {
      most_recent = true
      configuration_values = jsonencode({
        computeType = "Fargate"
        # Resources for CoreDNS
      })
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent              = true
      service_account_role_arn = module.vpc_cni_irsa.iam_role_arn
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  # Access management
  enable_cluster_creator_admin_permissions = true

  tags = merge(var.tags, {
    Module      = "eks"
    Environment = var.environment
  })
}

# -----------------------------------------------------------------------------
# IRSA: VPC CNI
# -----------------------------------------------------------------------------

module "vpc_cni_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.37"

  role_name             = "${var.project_name}-${var.environment}-vpc-cni"
  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# IRSA: EBS CSI Driver
# -----------------------------------------------------------------------------

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.37"

  role_name             = "${var.project_name}-${var.environment}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# IRSA: Cluster Autoscaler
# -----------------------------------------------------------------------------

module "cluster_autoscaler_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.37"

  role_name                        = "${var.project_name}-${var.environment}-cluster-autoscaler"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [module.eks.cluster_name]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# IRSA: AWS Load Balancer Controller
# -----------------------------------------------------------------------------

module "lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.37"

  role_name                              = "${var.project_name}-${var.environment}-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# IRSA: External Secrets Operator
# -----------------------------------------------------------------------------

module "external_secrets_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.37"

  role_name                             = "${var.project_name}-${var.environment}-external-secrets"
  attach_external_secrets_policy        = true
  external_secrets_secrets_manager_arns = var.secrets_manager_arns

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# KMS Key for cluster encryption (if not provided)
# -----------------------------------------------------------------------------

resource "aws_kms_key" "eks" {
  count = var.kms_key_arn == "" ? 1 : 0

  description             = "EKS cluster encryption key for ${var.project_name}-${var.environment}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-eks-encryption"
  })
}

resource "aws_kms_alias" "eks" {
  count = var.kms_key_arn == "" ? 1 : 0

  name          = "alias/${var.project_name}-${var.environment}-eks"
  target_key_id = aws_kms_key.eks[0].key_id
}
