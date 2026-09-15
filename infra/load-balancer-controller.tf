# Um controlador compartilhado: registra pods em TGs criados pelo root backend/.
# Nao recebe permissao de criar ALB, TG ou editar Security Groups.
resource "aws_iam_role" "load_balancer_controller" {
  count = var.academy_role_arn == null ? 1 : 0
  name  = "${local.platform_name}-targetgroup-controller"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.cluster[0].arn }
      Condition = { StringEquals = {
        "${local.oidc_host}:aud" = "sts.amazonaws.com"
        "${local.oidc_host}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
      } }
    }]
  })
}
resource "aws_iam_role_policy" "target_registration" {
  count = var.academy_role_arn == null ? 1 : 0
  name  = "existing-target-groups"
  role  = aws_iam_role.load_balancer_controller[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DiscoverTargets"
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs", "ec2:DescribeSecurityGroups", "ec2:DescribeInstances",
          "elasticloadbalancing:DescribeTargetGroups", "elasticloadbalancing:DescribeTargetHealth"
        ]
        Resource = "*"
      },
      {
        Sid    = "RegisterProjectTargets"
        Effect = "Allow"
        Action = ["elasticloadbalancing:RegisterTargets", "elasticloadbalancing:DeregisterTargets"]
        Resource = [for environment in keys(var.environments) :
          "arn:${data.aws_partition.current.partition}:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:targetgroup/${substr(var.project_name, 0, 12)}-${environment}-${substr(sha256(var.project_name), 0, 6)}/*"
        ]
      }
    ]
  })
}
output "load_balancer_controller_values" {
  description = "Helm values para instalar UM controlador no cluster. Somente configuracao; Terraform nao instala Helm."
  value = yamlencode({
    clusterName  = aws_eks_cluster.platform.name
    region       = var.aws_region
    vpcId        = aws_vpc.platform.id
    replicaCount = 2
    hostNetwork  = var.academy_role_arn != null
    dnsPolicy    = var.academy_role_arn != null ? "ClusterFirstWithHostNet" : "ClusterFirst"
    serviceAccount = {
      create      = true
      name        = "aws-load-balancer-controller"
      annotations = var.academy_role_arn != null ? {} : { "eks.amazonaws.com/role-arn" = aws_iam_role.load_balancer_controller[0].arn }
    }
    createIngressClassResource            = false
    ingressClassParams                    = { create = false }
    enableServiceMutatorWebhook           = false
    enableBackendSecurityGroup            = false
    enableManageBackendSecurityGroupRules = false
    enableShield                          = false
    enableWaf                             = false
    enableWafv2                           = false
    defaultTargetType                     = "ip"
    controllerConfig = { featureGates = {
      EnableServiceController = false
      ALBGatewayAPI           = false
      NLBGatewayAPI           = false
    } }
  })
}
