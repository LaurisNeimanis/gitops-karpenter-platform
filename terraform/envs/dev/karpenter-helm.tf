resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = var.karpenter_namespace
  create_namespace = true

  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.8.3"

  values = [
    yamlencode({
      settings = {
        clusterName       = module.eks.cluster_name
        interruptionQueue = aws_sqs_queue.karpenter_interruption.name
      }

      serviceAccount = {
        create = true
        name   = var.karpenter_service_account_name
      }

      controller = {
        resources = {
          requests = {
            cpu    = "500m"
            memory = "512Mi"
          }
          limits = {
            cpu    = "1"
            memory = "1Gi"
          }
        }

        nodeSelector = {
          "karpenter.sh/controller" = "true"
        }
      }

      logLevel = "info"
    })
  ]

  depends_on = [
    module.eks,
    aws_eks_pod_identity_association.karpenter_controller,
    aws_sqs_queue.karpenter_interruption
  ]
}
