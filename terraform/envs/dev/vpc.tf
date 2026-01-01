# -----------------------------------------------------
# VPC (official module v6)
# -----------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = local.resource_prefix
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  # NAT gateway for private subnets.
  # Cost-optimized setup: single NAT gateway (dev/demo).
  # In production, NAT gateways are typically deployed per AZ for higher availability.
  enable_nat_gateway = true
  single_nat_gateway = true

  # Required for EKS and internal DNS
  enable_dns_support   = true
  enable_dns_hostnames = true

  # Public subnets do NOT auto-assign public IPv4 addresses (intentional, even for demo)
  map_public_ip_on_launch = false

  # Do NOT touch AWS default VPC objects (EKS recommendation)
  manage_default_security_group = false
  manage_default_route_table    = false
  manage_default_network_acl    = false

  # Kubernetes load balancer tags (public = internet-facing)
  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  # Private subnets for internal load balancers / nodes
  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"

    "karpenter.sh/discovery" = local.cluster_name
  }

  # Enable VPC Flow Logs for network traffic visibility and troubleshooting
  enable_flow_log                      = true
  flow_log_destination_type            = "cloud-watch-logs"
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60 # 1-minute aggregation for near real-time analysis

  tags = local.tags
}

# -----------------------------------------------------
# Default VPC security group (locked down)
# -----------------------------------------------------
resource "aws_default_security_group" "default" {
  vpc_id = module.vpc.vpc_id

  ingress = []
  egress  = []

  tags = merge(
    local.tags,
    { Name = "${local.resource_prefix}-default-sg" }
  )

  lifecycle {
    ignore_changes = [
      tags["Name"],
      tags_all["Name"],
    ]
  }
}
