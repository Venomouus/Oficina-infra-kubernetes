locals {
  name = "${var.project_name}-${var.environment}-gateway"
  auth_routes = var.authentication == null ? toset([]) : toset([
    "POST /auth/cpf", "GET /.well-known/jwks.json", "GET /.well-known/openid-configuration"
  ])
  customer_routes = var.customer_backend == null ? toset([]) : toset([
    "GET /api/minhas-ordens-servico", "POST /api/minhas-ordens-servico",
    "GET /api/minhas-ordens-servico/{id}", "POST /api/minhas-ordens-servico/{id}/aprovar"
  ])
}
resource "aws_apigatewayv2_api" "gateway" {
  name          = local.name
  protocol_type = "HTTP"
  description   = "Autenticacao e rotas de cliente da oficina - ${var.environment}"
}
resource "aws_cloudwatch_log_group" "gateway" {
  name              = "/aws/apigateway/${local.name}"
  retention_in_days = 7
}
resource "aws_apigatewayv2_stage" "gateway" {
  depends_on  = [aws_apigatewayv2_route.authentication]
  api_id      = aws_apigatewayv2_api.gateway.id
  name        = "$default"
  auto_deploy = true
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.gateway.arn
    format = jsonencode({
      requestId          = "$context.requestId"
      routeKey           = "$context.routeKey"
      stage              = "$context.stage"
      status             = "$context.status"
      responseLength     = "$context.responseLength"
      integrationLatency = "$context.integrationLatency"
    })
  }
  default_route_settings {
    throttling_rate_limit    = var.throttling.rate
    throttling_burst_limit   = var.throttling.burst
    detailed_metrics_enabled = true
  }
  dynamic "route_settings" {
    for_each = var.authentication == null ? [] : ["POST /auth/cpf"]
    content {
      route_key                = route_settings.value
      throttling_rate_limit    = var.throttling.auth_rate
      throttling_burst_limit   = var.throttling.auth_burst
      detailed_metrics_enabled = true
    }
  }
}
resource "aws_apigatewayv2_integration" "authentication" {
  count                  = var.authentication == null ? 0 : 1
  api_id                 = aws_apigatewayv2_api.gateway.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${var.authentication.alias_arn}/invocations"
  payload_format_version = "2.0"
  timeout_milliseconds   = 20000
  lifecycle {
    precondition {
      condition     = var.authentication.issuer == aws_apigatewayv2_api.gateway.api_endpoint
      error_message = "Issuer da Lambda deve corresponder exatamente a URL HTTPS deste Gateway."
    }
  }
}
resource "aws_apigatewayv2_route" "authentication" {
  for_each           = local.auth_routes
  api_id             = aws_apigatewayv2_api.gateway.id
  route_key          = each.value
  authorization_type = "NONE"
  target             = "integrations/${aws_apigatewayv2_integration.authentication[0].id}"
}
resource "aws_apigatewayv2_authorizer" "customer" {
  count            = var.jwt_ready ? 1 : 0
  api_id           = aws_apigatewayv2_api.gateway.id
  name             = "cliente-rs256"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  jwt_configuration {
    issuer   = aws_apigatewayv2_api.gateway.api_endpoint
    audience = [var.jwt_audience]
  }
  depends_on = [aws_apigatewayv2_route.authentication, aws_apigatewayv2_stage.gateway]
}
data "aws_lb_listener" "customer" {
  count = var.customer_backend == null ? 0 : 1
  arn   = var.customer_backend.listener_arn
}
data "aws_lb" "customer" {
  count = var.customer_backend == null ? 0 : 1
  arn   = data.aws_lb_listener.customer[0].load_balancer_arn
}
resource "aws_apigatewayv2_integration" "customer" {
  count                  = var.customer_backend == null ? 0 : 1
  api_id                 = aws_apigatewayv2_api.gateway.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = var.customer_backend.listener_arn
  connection_type        = "VPC_LINK"
  connection_id          = var.customer_backend.vpc_link_id
  payload_format_version = "1.0"
  timeout_milliseconds   = 29000
  request_parameters     = { "overwrite:path" = "$request.path" }
  dynamic "tls_config" {
    for_each = var.customer_backend.server_name_to_verify == null ? [] : [var.customer_backend.server_name_to_verify]
    content { server_name_to_verify = tls_config.value }
  }
  lifecycle {
    precondition {
      condition = (
        data.aws_lb.customer[0].internal &&
        data.aws_lb.customer[0].load_balancer_type == "application" &&
        data.aws_lb.customer[0].vpc_id == var.customer_backend.vpc_id &&
        (data.aws_lb_listener.customer[0].protocol == "HTTPS" ?
          var.customer_backend.server_name_to_verify != null :
        data.aws_lb_listener.customer[0].protocol == "HTTP" && var.customer_backend.server_name_to_verify == null)
      )
      error_message = "Backend deve ser ALB interno na VPC indicada, com listener HTTP ou HTTPS com verificacao TLS."
    }
  }
}
resource "aws_apigatewayv2_route" "customer" {
  for_each             = local.customer_routes
  api_id               = aws_apigatewayv2_api.gateway.id
  route_key            = each.value
  authorization_type   = "JWT"
  authorizer_id        = aws_apigatewayv2_authorizer.customer[0].id
  authorization_scopes = ["oficina:cliente"]
  target               = "integrations/${aws_apigatewayv2_integration.customer[0].id}"
}
