mock_provider "aws" {
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_eks_addon_version" { defaults = { version = "v1.0.0-eksbuild.1" } }
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-1:123456789012:cluster/oficina-lab-eks"
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/TEST" }] }]
      certificate_authority = [{ data = "dGVzdA==" }]
    }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/TEST" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/test-role" }
  }
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-0123456789abcdef0", latest_version = 1 }
  }
}
variables {
  aws_account_id               = "123456789012"
  cluster_admin_principal_arns = ["arn:aws:iam::123456789012:role/OficinaPlatformAdmin"]
}
run "controller_has_scoped_target_registration_and_irsa" {
  command = apply
  assert {
    condition = (
      jsondecode(aws_iam_role.load_balancer_controller[0].assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity" &&
      jsondecode(aws_iam_role.load_balancer_controller[0].assume_role_policy).Statement[0].Condition.StringEquals["${local.oidc_host}:sub"] == "system:serviceaccount:kube-system:aws-load-balancer-controller" &&
      jsondecode(aws_iam_role.load_balancer_controller[0].assume_role_policy).Statement[0].Condition.StringEquals["${local.oidc_host}:aud"] == "sts.amazonaws.com" &&
      jsondecode(aws_iam_role.load_balancer_controller[0].assume_role_policy).Statement[0].Principal.Federated == aws_iam_openid_connect_provider.cluster[0].arn
    )
    error_message = "IRSA deve aceitar somente o service account do controlador neste cluster."
  }
  assert {
    condition = (
      toset(jsondecode(aws_iam_role_policy.target_registration[0].policy).Statement[1].Action) ==
      toset(["elasticloadbalancing:RegisterTargets", "elasticloadbalancing:DeregisterTargets"]) &&
      toset(jsondecode(aws_iam_role_policy.target_registration[0].policy).Statement[1].Resource) ==
      toset([for environment in ["staging", "producao"] :
        "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/oficina-${environment}-${substr(sha256("oficina"), 0, 6)}/*"
      ]) &&
      alltrue([for action in jsondecode(aws_iam_role_policy.target_registration[0].policy).Statement[0].Action : strcontains(action, ":Describe")])
    )
    error_message = "Controlador so deve descrever e registrar/remover targets nos TGs do projeto; sem criacao de ALB ou edicao de SG."
  }
  assert {
    condition = (
      yamldecode(output.load_balancer_controller_values).serviceAccount.annotations["eks.amazonaws.com/role-arn"] == aws_iam_role.load_balancer_controller[0].arn &&
      yamldecode(output.load_balancer_controller_values).vpcId == aws_vpc.platform.id &&
      yamldecode(output.load_balancer_controller_values).clusterName == aws_eks_cluster.platform.name &&
      !yamldecode(output.load_balancer_controller_values).enableBackendSecurityGroup &&
      !yamldecode(output.load_balancer_controller_values).enableServiceMutatorWebhook &&
      !yamldecode(output.load_balancer_controller_values).controllerConfig.featureGates.EnableServiceController
    )
    error_message = "Helm deve receber IRSA, regiao/VPC explicitas e desativar gerencia automatica de SG/Service."
  }
}
