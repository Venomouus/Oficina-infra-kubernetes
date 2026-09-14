output "customer_backend" {
  description = "Entrada customer_backend do gateway/ do MESMO ambiente. Sem segredos."
  value = {
    vpc_id                = var.platform.vpc_id
    vpc_link_id           = aws_apigatewayv2_vpc_link.api.id
    listener_arn          = aws_lb_listener.api.arn
    server_name_to_verify = var.listener_tls == null ? null : var.listener_tls.server_name_to_verify
  }
}
output "backend" {
  description = "Identificacao do ambiente e recursos para validar a integracao real."
  value = {
    contract_version = 1
    environment      = var.environment
    aws_region       = var.aws_region
    cluster_name     = var.platform.cluster_name
    namespace        = local.namespace
    alb_arn          = aws_lb.api.arn
    alb_dns_name     = aws_lb.api.dns_name
    target_group_arn = aws_lb_target_group.api.arn
  }
}
output "kubernetes_manifest" {
  description = "Service ClusterIP e TGB para instalar somente apos o controlador e o namespace existirem. Nao cria Deployment."
  value = join("---\n", [yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata   = { name = "oficina-api", namespace = local.namespace }
    spec = {
      type     = "ClusterIP"
      selector = { app = "oficina-api" }
      ports    = [{ name = "http", port = 8080, targetPort = 8080, protocol = "TCP" }]
    }
    }), yamlencode({
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata   = { name = "oficina-api", namespace = local.namespace }
    spec = {
      serviceRef     = { name = "oficina-api", port = 8080 }
      targetGroupARN = aws_lb_target_group.api.arn
      targetType     = "ip"
      vpcID          = var.platform.vpc_id
      # Sem networking: SGs pertencem ao Terraform, nao ao controlador.
    }
  })])
}
