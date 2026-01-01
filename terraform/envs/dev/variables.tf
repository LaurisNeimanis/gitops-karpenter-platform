variable "aws_region" {
  type        = string
  description = "AWS region (e.g. eu-central-1)."
}

variable "name" {
  type        = string
  description = "Base name/prefix for all resources (VPC, EKS, etc.)."
}

variable "environment" {
  type        = string
  description = "Environment name (dev, stage, prod)"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
}

variable "public_subnets" {
  type        = list(string)
  description = "CIDR blocks for public subnets."
}

variable "private_subnets" {
  type        = list(string)
  description = "CIDR blocks for private subnets used by EKS nodes."
}

variable "azs" {
  type        = list(string)
  description = "Availability Zones matching the subnet definitions."
}

variable "cluster_version" {
  type        = string
  description = "Kubernetes version for the EKS cluster (e.g. 1.34)."
}

variable "node_instance_types" {
  type        = list(string)
  description = <<EOF
Ordered list of EC2 instance types for EKS managed node groups.

Instance type selection strategy:
- First entry is the primary instance type
- Subsequent entries act as capacity fallbacks
- Ordering is intentional and environment-specific
EOF
}

variable "node_desired_size" {
  type        = number
  description = "Desired node count for the managed node group."
}

variable "node_min_size" {
  type        = number
  description = "Minimum node count for the managed node group."
}

variable "node_max_size" {
  type        = number
  description = "Maximum node count for the managed node group."
}

variable "node_disk_size" {
  type        = number
  description = "Disk size in GB for worker nodes."
  default     = 20
}

variable "eks_public_access_cidrs" {
  description = "CIDR blocks allowed to access the EKS public API endpoint"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional / override tags"
  type        = map(string)
  default     = {}
}
