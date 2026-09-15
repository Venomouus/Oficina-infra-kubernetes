resource "aws_iam_role" "cluster" {
  count = var.academy_role_arn == null ? 1 : 0
  name  = "${local.platform_name}-eks-control-plane"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "eks.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  count      = var.academy_role_arn == null ? 1 : 0
  role       = aws_iam_role.cluster[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.log_retention_days
}

resource "aws_eks_cluster" "platform" {
  name                          = local.cluster_name
  role_arn                      = var.academy_role_arn != null ? var.academy_role_arn : aws_iam_role.cluster[0].arn
  version                       = var.kubernetes_version
  bootstrap_self_managed_addons = false
  enabled_cluster_log_types     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  upgrade_policy { support_type = "STANDARD" }

  vpc_config {
    subnet_ids              = [for subnet in aws_subnet.private : subnet.id]
    endpoint_private_access = true
    endpoint_public_access  = length(var.eks_public_access_cidrs) > 0
    public_access_cidrs     = length(var.eks_public_access_cidrs) > 0 ? var.eks_public_access_cidrs : null
  }

  depends_on = [aws_iam_role_policy_attachment.cluster, aws_cloudwatch_log_group.cluster]
}

resource "aws_eks_access_entry" "administrator" {
  for_each      = var.cluster_admin_principal_arns
  cluster_name  = aws_eks_cluster.platform.name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "administrator" {
  for_each      = var.cluster_admin_principal_arns
  cluster_name  = aws_eks_cluster.platform.name
  principal_arn = aws_eks_access_entry.administrator[each.key].principal_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
}

resource "aws_iam_openid_connect_provider" "cluster" {
  count          = var.academy_role_arn == null ? 1 : 0
  url            = aws_eks_cluster.platform.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  oidc_host = replace(aws_eks_cluster.platform.identity[0].oidc[0].issuer, "https://", "")
}

# Credencial exclusiva do aws-node. Nao anexar CNI policy ao IAM role dos workers.
resource "aws_iam_role" "vpc_cni" {
  count = var.academy_role_arn == null ? 1 : 0
  name  = "${local.platform_name}-vpc-cni"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.cluster[0].arn }
      Condition = { StringEquals = {
        "${local.oidc_host}:aud" = "sts.amazonaws.com"
        "${local.oidc_host}:sub" = "system:serviceaccount:kube-system:aws-node"
      } }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  count      = var.academy_role_arn == null ? 1 : 0
  role       = aws_iam_role.vpc_cni[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Valores resolvidos pela AWS na versao do cluster; fixe overrides no tfvars
# depois de validar o primeiro plan autenticado.
data "aws_eks_addon_version" "platform" {
  for_each           = toset(["vpc-cni", "kube-proxy", "coredns", "metrics-server"])
  addon_name         = each.key
  kubernetes_version = var.kubernetes_version
  most_recent        = false
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.platform.name
  addon_name                  = "vpc-cni"
  addon_version               = coalesce(var.addon_versions["vpc-cni"], data.aws_eks_addon_version.platform["vpc-cni"].version)
  service_account_role_arn    = var.academy_role_arn != null ? null : aws_iam_role.vpc_cni[0].arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  configuration_values        = jsonencode({ enableNetworkPolicy = "true" })
  depends_on                  = [aws_iam_role_policy_attachment.vpc_cni]
}

resource "aws_iam_role" "nodes" {
  count = var.academy_role_arn == null ? 1 : 0
  name  = "${local.platform_name}-eks-workers"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "nodes" {
  for_each   = var.academy_role_arn != null ? toset([]) : toset(["AmazonEKSWorkerNodePolicy", "AmazonEC2ContainerRegistryPullOnly"])
  role       = aws_iam_role.nodes[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.key}"
}

resource "aws_launch_template" "nodes" {
  name_prefix            = "${local.platform_name}-workers-"
  update_default_version = true
  vpc_security_group_ids = [aws_eks_cluster.platform.vpc_config[0].cluster_security_group_id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }
  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${local.platform_name}-worker" })
  }
}

resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.platform.name
  node_group_name = "${local.platform_name}-workers"
  node_role_arn   = var.academy_role_arn != null ? var.academy_role_arn : aws_iam_role.nodes[0].arn
  subnet_ids      = [for subnet in aws_subnet.private : subnet.id]
  version         = var.kubernetes_version
  ami_type        = "AL2023_x86_64_STANDARD"
  capacity_type   = "ON_DEMAND"
  instance_types  = [var.node_instance_type]

  launch_template {
    id      = aws_launch_template.nodes.id
    version = aws_launch_template.nodes.latest_version
  }
  scaling_config {
    min_size     = var.node_scaling.min
    desired_size = var.node_scaling.desired
    max_size     = var.node_scaling.max
  }
  update_config { max_unavailable = 1 }

  depends_on = [
    aws_iam_role_policy_attachment.nodes, aws_eks_addon.vpc_cni,
    aws_route.private_egress, aws_route_table_association.private, aws_route.internet
  ]
}

resource "aws_eks_addon" "runtime" {
  for_each                    = toset(["kube-proxy", "coredns", "metrics-server"])
  cluster_name                = aws_eks_cluster.platform.name
  addon_name                  = each.key
  addon_version               = coalesce(var.addon_versions[each.key], data.aws_eks_addon_version.platform[each.key].version)
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  depends_on                  = [aws_eks_node_group.workers]
}
