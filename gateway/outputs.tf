output "gateway" {
  description = "Contrato para configurar issuer e permissao no Oficina-serverless."
  value = {
    contract_version      = 1
    environment           = var.environment
    aws_region            = var.aws_region
    api_id                = aws_apigatewayv2_api.gateway.id
    issuer                = aws_apigatewayv2_api.gateway.api_endpoint
    audience              = var.jwt_audience
    execution_arn         = aws_apigatewayv2_api.gateway.execution_arn
    stage                 = aws_apigatewayv2_stage.gateway.name
    jwt_authorizer_id     = try(aws_apigatewayv2_authorizer.customer[0].id, null)
    authentication_routes = local.auth_routes
    customer_routes       = local.customer_routes
  }
}
