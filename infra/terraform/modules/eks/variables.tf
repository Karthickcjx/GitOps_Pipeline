# =============================================================================
# EKS Module — Variables
# =============================================================================

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (staging, production)"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.29"
}

variable "vpc_id" {
  description = "VPC ID where the EKS cluster will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for worker nodes"
  type        = list(string)
}

variable "cluster_endpoint_public_access" {
  description = "Whether the EKS API server endpoint is publicly accessible"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for cluster encryption. If empty, a new key is created."
  type        = string
  default     = ""
}

# Node group configuration
variable "node_instance_types" {
  description = "Instance types for the general-purpose node group"
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_min_size" {
  description = "Minimum number of nodes in the general node group"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes in the general node group"
  type        = number
  default     = 10
}

variable "node_desired_size" {
  description = "Desired number of nodes in the general node group"
  type        = number
  default     = 2
}

# Spot configuration
variable "spot_instance_types" {
  description = "Instance types for the spot node group"
  type        = list(string)
  default     = ["t3.large", "t3a.large"]
}

variable "spot_max_size" {
  description = "Maximum number of spot instances"
  type        = number
  default     = 5
}

# IRSA
variable "secrets_manager_arns" {
  description = "ARNs of Secrets Manager secrets accessible by External Secrets Operator"
  type        = list(string)
  default     = ["arn:aws:secretsmanager:*:*:secret:gitops-platform/*"]
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
