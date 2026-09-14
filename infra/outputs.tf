output "platform" {
  description = "Contrato versionado para os demais repositorios. IDs somente existem apos apply."
  value = {
    contract_version    = 1
    aws_region          = var.aws_region
    vpc_id              = aws_vpc.platform.id
    cluster_name        = aws_eks_cluster.platform.name
    cluster_arn         = aws_eks_cluster.platform.arn
    oidc_provider_arn   = aws_iam_openid_connect_provider.cluster.arn
    oidc_issuer_url     = aws_eks_cluster.platform.identity[0].oidc[0].issuer
    public_subnet_ids   = [for subnet in aws_subnet.public : subnet.id]
    private_subnet_ids  = [for subnet in aws_subnet.private : subnet.id]
    database_subnet_ids = [for subnet in aws_subnet.database : subnet.id]
    # SG compartilhado por nodes/pods; nao representa isolamento por namespace.
    application_security_group_id = aws_eks_cluster.platform.vpc_config[0].cluster_security_group_id
    lambda_security_group_ids     = { for name, group in aws_security_group.lambda : name => group.id }
    environments                  = var.environments
  }
}

output "cluster_endpoint" {
  description = "Endpoint de administracao Kubernetes; nao e a URL da API da oficina."
  value       = aws_eks_cluster.platform.endpoint
}

output "cluster_certificate_authority_data" {
  description = "CA publica do cluster para integracoes Kubernetes."
  value       = aws_eks_cluster.platform.certificate_authority[0].data
}

output "resolved_addon_versions" {
  description = "Versoes dos addons; registrar como overrides antes da promocao."
  value = merge(
    { "vpc-cni" = aws_eks_addon.vpc_cni.addon_version },
    { for name, addon in aws_eks_addon.runtime : name => addon.addon_version }
  )
}
