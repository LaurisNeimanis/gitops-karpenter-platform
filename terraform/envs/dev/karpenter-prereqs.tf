# ------------------------------------------------------------------------------
# Karpenter prerequisites (AWS-side)
# ------------------------------------------------------------------------------

variable "karpenter_namespace" {
  type        = string
  description = "Namespace where Karpenter runs (service account lives here)."
  default     = "karpenter"
}

variable "karpenter_service_account_name" {
  type        = string
  description = "Karpenter controller ServiceAccount name."
  default     = "karpenter"
}

variable "enable_karpenter_node_ssm" {
  type        = bool
  description = "Attach AmazonSSMManagedInstanceCore to Karpenter nodes (optional)."
  default     = false
}

locals {
  karpenter_discovery_tag_key   = "karpenter.sh/discovery"
  karpenter_discovery_tag_value = local.cluster_name
}

data "aws_caller_identity" "current" {}

# ------------------------------------------------------------------------------
# SQS interruption queue
# ------------------------------------------------------------------------------

resource "aws_sqs_queue" "karpenter_interruption" {
  name                       = "${local.resource_prefix}-karpenter-interruption"
  message_retention_seconds  = 1209600
  visibility_timeout_seconds = 60
  sqs_managed_sse_enabled    = true

  tags = merge(local.tags, {
    Name  = "${local.resource_prefix}-karpenter-interruption"
    Scope = "karpenter"
  })
}

data "aws_iam_policy_document" "karpenter_sqs_policy" {
  statement {
    sid    = "AllowEventBridgeSendMessage"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.karpenter_interruption.arn]
  }
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id
  policy    = data.aws_iam_policy_document.karpenter_sqs_policy.json
}

# ------------------------------------------------------------------------------
# EventBridge → SQS
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "karpenter_spot_interruption" {
  name        = "${local.resource_prefix}-karpenter-spot-interruption"
  description = "EC2 Spot Instance Interruption Warning → Karpenter"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })

  tags = merge(local.tags, { Scope = "karpenter" })
}

resource "aws_cloudwatch_event_target" "karpenter_spot_interruption" {
  rule      = aws_cloudwatch_event_rule.karpenter_spot_interruption.name
  target_id = "sqs"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_rule" "karpenter_rebalance" {
  name        = "${local.resource_prefix}-karpenter-rebalance"
  description = "EC2 Rebalance Recommendation → Karpenter"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })

  tags = merge(local.tags, { Scope = "karpenter" })
}

resource "aws_cloudwatch_event_target" "karpenter_rebalance" {
  rule      = aws_cloudwatch_event_rule.karpenter_rebalance.name
  target_id = "sqs"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_rule" "karpenter_instance_state_change" {
  name        = "${local.resource_prefix}-karpenter-instance-state-change"
  description = "EC2 State Change → Karpenter"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })

  tags = merge(local.tags, { Scope = "karpenter" })
}

resource "aws_cloudwatch_event_target" "karpenter_instance_state_change" {
  rule      = aws_cloudwatch_event_rule.karpenter_instance_state_change.name
  target_id = "sqs"
  arn       = aws_sqs_queue.karpenter_interruption.arn
}

# ------------------------------------------------------------------------------
# Node role + instance profile
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "karpenter_node_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "karpenter_node" {
  name               = "${local.resource_prefix}-karpenter-node"
  assume_role_policy = data.aws_iam_policy_document.karpenter_node_assume_role.json
  tags               = merge(local.tags, { Scope = "karpenter" })
}

resource "aws_iam_role_policy_attachment" "karpenter_node_worker" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ecr" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ssm" {
  count      = var.enable_karpenter_node_ssm ? 1 : 0
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "karpenter" {
  name = "${local.resource_prefix}-karpenter-node"
  role = aws_iam_role.karpenter_node.name
  tags = merge(local.tags, { Scope = "karpenter" })
}

# ------------------------------------------------------------------------------
# EKS Pod Identity role for Karpenter controller
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "karpenter_controller_assume_role" {
  statement {
    effect  = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values = [
        module.eks.cluster_arn
      ]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name               = "${local.resource_prefix}-karpenter-controller"
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_assume_role.json
  tags               = merge(local.tags, { Scope = "karpenter" })
}

resource "aws_eks_pod_identity_association" "karpenter_controller" {
  cluster_name    = module.eks.cluster_name
  namespace       = var.karpenter_namespace
  service_account = var.karpenter_service_account_name
  role_arn        = aws_iam_role.karpenter_controller.arn
}

# ------------------------------------------------------------------------------
# Controller policy (LaunchTemplate auth bug fixed)
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "karpenter_controller" {

  # --------------------------------------------------
  # EKS cluster read
  # --------------------------------------------------
  statement {
    sid       = "EKSDescribeCluster"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [module.eks.cluster_arn]
  }

  # --------------------------------------------------
  # EC2 read (discovery)
  # --------------------------------------------------
  statement {
    sid    = "ReadOnlyEC2"
    effect = "Allow"
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeVpcs",
      "ec2:DescribeTags",
      "ec2:DescribeRouteTables",
    ]
    resources = ["*"]
  }

  # --------------------------------------------------
  # EC2 Launch Templates
  # --------------------------------------------------
  statement {
    sid    = "EC2LaunchTemplateManagement"
    effect = "Allow"
    actions = [
      "ec2:CreateLaunchTemplate",
      "ec2:CreateLaunchTemplateVersion",
      "ec2:DeleteLaunchTemplate",
      "ec2:DeleteLaunchTemplateVersions",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:GetLaunchTemplateData",
    ]
    resources = ["*"]
  }

  # --------------------------------------------------
  # EC2 instance lifecycle
  # --------------------------------------------------
  statement {
    sid    = "EC2InstanceProvisioning"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
      "ec2:TerminateInstances",
    ]
    resources = ["*"]
  }

  # --------------------------------------------------
  # EC2 tagging
  # --------------------------------------------------
  statement {
    sid    = "EC2Tagging"
    effect = "Allow"
    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["*"]
  }

  # --------------------------------------------------
  # Pricing API (OBLIGĀTS)
  # --------------------------------------------------
  statement {
    sid       = "PricingRead"
    effect    = "Allow"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  # --------------------------------------------------
  # Instance Profile discovery (OBLIGĀTS)
  # --------------------------------------------------
  statement {
    sid    = "InstanceProfileRead"
    effect = "Allow"
    actions = [
      "iam:ListInstanceProfiles",
      "iam:GetInstanceProfile",
    ]
    resources = ["*"]
  }

  # --------------------------------------------------
  # Pass ONLY node role
  # --------------------------------------------------
  statement {
    sid       = "PassNodeRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.karpenter_node.arn]
  }

  # --------------------------------------------------
  # SSM for AMI alias resolution (al2023@latest)
  # --------------------------------------------------
  statement {
    sid    = "SSMParameterRead"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = ["*"]
  }

  # --------------------------------------------------
  # SQS interruption handling
  # --------------------------------------------------
  statement {
    sid    = "SQSConsume"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = [aws_sqs_queue.karpenter_interruption.arn]
  }
}

resource "aws_iam_policy" "karpenter_controller" {
  name   = "${local.resource_prefix}-karpenter-controller"
  policy = data.aws_iam_policy_document.karpenter_controller.json
  tags   = merge(local.tags, { Scope = "karpenter" })
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  role       = aws_iam_role.karpenter_controller.name
  policy_arn = aws_iam_policy.karpenter_controller.arn
}

resource "aws_eks_access_entry" "karpenter_node" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.karpenter_node.arn
  type          = "EC2_LINUX"
}
