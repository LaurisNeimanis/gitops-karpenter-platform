# -----------------------------------------------------
# EKS (official module v21)
# -----------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = local.cluster_name
  kubernetes_version = var.cluster_version

  enable_cluster_creator_admin_permissions = var.environment == "dev"
  authentication_mode                      = "API"

  endpoint_public_access       = true
  endpoint_private_access      = true
  endpoint_public_access_cidrs = var.eks_public_access_cidrs

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  addons = {
    coredns        = {}
    kube-proxy     = {}
    metrics-server = {}

    vpc-cni = {
      before_compute = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }

    eks-pod-identity-agent = {
      before_compute = true
    }
  }

  create_kms_key = true

  encryption_config = {
    resources = ["secrets"]
  }

  enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]

  # -----------------------------------------------------
  # Managed node group (bootstrap/system)
  # -----------------------------------------------------
  eks_managed_node_groups = {
    system = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.node_instance_types

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      disk_size = var.node_disk_size

      labels = {
        "karpenter.sh/controller" = "true"
      }

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
        instance_metadata_tags      = "disabled"
      }
    }
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = local.cluster_name
  }

  tags = local.tags
}


# ------------------------------------------------------------------------------
# Allow VPC-internal traffic to NodePorts (required for EKS LoadBalancers)
#
# Explanation:
#   - AWS Load Balancers (ALB/NLB) always forward traffic to NodePort targets.
#   - NodePort values are dynamic (30000–32767), therefore ports cannot be
#     safely whitelisted individually.
#   - This rule allows ONLY VPC-internal traffic (no public exposure) to reach
#     the worker nodes on any TCP port, as required by Kubernetes networking.
#
# Best practice:
#   - This is the official and recommended security model for EKS.
#   - External access remains restricted to LB listeners (80/443).
# ------------------------------------------------------------------------------

resource "aws_security_group_rule" "nodes_allow_all_from_vpc" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  security_group_id = module.eks.node_security_group_id
  cidr_blocks       = [module.vpc.vpc_cidr_block]
  description       = "Allow traffic inside VPC to reach NodePorts"
}
