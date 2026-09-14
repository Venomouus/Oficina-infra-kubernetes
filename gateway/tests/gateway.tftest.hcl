mock_provider "aws" {
  mock_resource "aws_apigatewayv2_api" {
    defaults = {
      id            = "abc123"
      api_endpoint  = "https://abc123.execute-api.us-east-1.amazonaws.com"
      execution_arn = "arn:aws:execute-api:us-east-1:123456789012:abc123"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/apigateway/oficina-staging-gateway" }
  }
  mock_data "aws_lb_listener" {
    defaults = {
      protocol          = "HTTPS"
      load_balancer_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/oficina/0123456789abcdef"
    }
  }
  mock_data "aws_lb" {
    defaults = {
      internal           = true
      load_balancer_type = "application"
      vpc_id             = "vpc-0123456789abcdef0"
    }
  }
}
variables { aws_account_id = "123456789012" }

run "bootstrap_has_no_public_business_routes" {
  command = apply
  assert {
    condition = (
      aws_apigatewayv2_api.gateway.protocol_type == "HTTP" &&
      aws_apigatewayv2_stage.gateway.name == "$default" &&
      aws_apigatewayv2_stage.gateway.auto_deploy &&
      length(aws_apigatewayv2_route.authentication) == 0 &&
      length(aws_apigatewayv2_route.customer) == 0 &&
      length(aws_apigatewayv2_authorizer.customer) == 0 &&
      output.gateway.execution_arn == "arn:aws:execute-api:us-east-1:123456789012:abc123"
    )
    error_message = "Bootstrap deve fornecer HTTPS/execution ARN sem expor rotas antes de configurar destinos."
  }
  assert {
    condition = (
      aws_cloudwatch_log_group.gateway.retention_in_days == 7 &&
      toset(keys(jsondecode(aws_apigatewayv2_stage.gateway.access_log_settings[0].format))) ==
      toset(["requestId", "routeKey", "stage", "status", "responseLength", "integrationLatency"])
    )
    error_message = "Logs devem ter retencao e excluir corpos, tokens, CPF e mensagens internas."
  }
}
run "authentication_uses_alias_and_public_discovery" {
  command = apply
  variables { authentication = {
    contract_version = 1
    environment      = "staging"
    aws_region       = "us-east-1"
    alias_arn        = "arn:aws:lambda:us-east-1:123456789012:function:oficina-staging-autenticacao:live"
    issuer           = "https://abc123.execute-api.us-east-1.amazonaws.com"
    audience         = "oficina-api"
  } }
  assert {
    condition = (
      toset(keys(aws_apigatewayv2_route.authentication)) == toset([
      "POST /auth/cpf", "GET /.well-known/jwks.json", "GET /.well-known/openid-configuration"]) &&
      alltrue([for route in aws_apigatewayv2_route.authentication : route.authorization_type == "NONE"]) &&
      aws_apigatewayv2_integration.authentication[0].payload_format_version == "2.0" &&
      endswith(aws_apigatewayv2_integration.authentication[0].integration_uri, ":live/invocations") &&
      length(aws_apigatewayv2_route.customer) == 0
    )
    error_message = "Somente auth/discovery/JWKS devem usar a Lambda live sem exigir JWT."
  }
  assert {
    condition = (
      aws_apigatewayv2_stage.gateway.default_route_settings[0].throttling_rate_limit == 5 &&
      anytrue([for setting in aws_apigatewayv2_stage.gateway.route_settings :
      setting.route_key == "POST /auth/cpf" && setting.throttling_rate_limit == 1 && setting.throttling_burst_limit == 2])
    )
    error_message = "A autenticacao deve ter limite mais restrito que as demais rotas."
  }
}
run "customer_routes_require_jwt_scope_and_private_backend" {
  command = apply
  variables {
    authentication = {
      contract_version = 1
      environment      = "staging"
      aws_region       = "us-east-1"
      alias_arn        = "arn:aws:lambda:us-east-1:123456789012:function:oficina-staging-autenticacao:live"
      issuer           = "https://abc123.execute-api.us-east-1.amazonaws.com"
      audience         = "oficina-api"
    }
    jwt_ready = true
    customer_backend = {
      vpc_id                = "vpc-0123456789abcdef0"
      vpc_link_id           = "vpc123"
      listener_arn          = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/oficina/0123456789abcdef/0123456789abcdef"
      server_name_to_verify = "api.internal.example.com"
    }
  }
  assert {
    condition = (
      aws_apigatewayv2_authorizer.customer[0].authorizer_type == "JWT" &&
      toset(aws_apigatewayv2_authorizer.customer[0].identity_sources) == toset(["$request.header.Authorization"]) &&
      aws_apigatewayv2_authorizer.customer[0].jwt_configuration[0].issuer == output.gateway.issuer &&
      toset(aws_apigatewayv2_authorizer.customer[0].jwt_configuration[0].audience) == toset(["oficina-api"]) &&
      length(aws_apigatewayv2_route.customer) == 4 &&
      alltrue([for route in aws_apigatewayv2_route.customer :
        route.authorization_type == "JWT" &&
        route.authorizer_id == aws_apigatewayv2_authorizer.customer[0].id &&
      toset(route.authorization_scopes) == toset(["oficina:cliente"])]) &&
      !contains(keys(aws_apigatewayv2_route.customer), "ANY /{proxy+}")
    )
    error_message = "Todas as rotas de cliente devem exigir JWT e escopo; nao publicar proxy generico ou rotas administrativas."
  }
  assert {
    condition = (
      aws_apigatewayv2_integration.customer[0].connection_type == "VPC_LINK" &&
      aws_apigatewayv2_integration.customer[0].connection_id == "vpc123" &&
      aws_apigatewayv2_integration.customer[0].request_parameters["overwrite:path"] == "$request.path" &&
      aws_apigatewayv2_integration.customer[0].tls_config[0].server_name_to_verify == "api.internal.example.com"
    )
    error_message = "Integracao privada deve preservar o caminho da API e verificar TLS no listener HTTPS."
  }
}
run "production_uses_its_own_lambda" {
  command = apply
  variables {
    environment = "producao"
    authentication = {
      contract_version = 1
      environment      = "producao"
      aws_region       = "us-east-1"
      alias_arn        = "arn:aws:lambda:us-east-1:123456789012:function:oficina-producao-autenticacao:live"
      issuer           = "https://abc123.execute-api.us-east-1.amazonaws.com"
      audience         = "oficina-api"
    }
  }
  assert {
    condition     = output.gateway.environment == "producao" && strcontains(aws_apigatewayv2_integration.authentication[0].integration_uri, ":oficina-producao-autenticacao:live/")
    error_message = "Producao deve integrar somente sua Lambda."
  }
}
run "reject_lambda_from_other_environment" {
  command = plan
  variables { authentication = {
    contract_version = 1
    environment      = "staging"
    aws_region       = "us-east-1"
    alias_arn        = "arn:aws:lambda:us-east-1:123456789012:function:oficina-producao-autenticacao:live"
    issuer           = "https://abc123.execute-api.us-east-1.amazonaws.com"
    audience         = "oficina-api"
  } }
  expect_failures = [var.authentication]
}
run "reject_issuer_mismatch" {
  command = plan
  variables { authentication = {
    contract_version = 1
    environment      = "staging"
    aws_region       = "us-east-1"
    alias_arn        = "arn:aws:lambda:us-east-1:123456789012:function:oficina-staging-autenticacao:live"
    issuer           = "https://wrong.example.com"
    audience         = "oficina-api"
  } }
  expect_failures = [aws_apigatewayv2_integration.authentication]
}
run "reject_jwt_without_authentication" {
  command = plan
  variables { jwt_ready = true }
  expect_failures = [var.jwt_ready]
}
run "reject_backend_without_jwt" {
  command = plan
  variables {
    authentication = {
      contract_version = 1
      environment      = "staging"
      aws_region       = "us-east-1"
      alias_arn        = "arn:aws:lambda:us-east-1:123456789012:function:oficina-staging-autenticacao:live"
      issuer           = "https://abc123.execute-api.us-east-1.amazonaws.com"
      audience         = "oficina-api"
    }
    customer_backend = {
      vpc_id                = "vpc-0123456789abcdef0"
      vpc_link_id           = "vpc123"
      listener_arn          = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/oficina/0123456789abcdef/0123456789abcdef"
      server_name_to_verify = "api.internal.example.com"
    }
  }
  expect_failures = [var.customer_backend]
}
run "reject_public_load_balancer" {
  command = plan
  variables {
    authentication = {
      contract_version = 1
      environment      = "staging"
      aws_region       = "us-east-1"
      alias_arn        = "arn:aws:lambda:us-east-1:123456789012:function:oficina-staging-autenticacao:live"
      issuer           = "https://abc123.execute-api.us-east-1.amazonaws.com"
      audience         = "oficina-api"
    }
    jwt_ready = true
    customer_backend = {
      vpc_id                = "vpc-0123456789abcdef0"
      vpc_link_id           = "vpc123"
      listener_arn          = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/oficina/0123456789abcdef/0123456789abcdef"
      server_name_to_verify = "api.internal.example.com"
    }
  }
  override_data {
    target = data.aws_lb.customer[0]
    values = { internal = false, load_balancer_type = "application", vpc_id = "vpc-0123456789abcdef0" }
  }
  expect_failures = [aws_apigatewayv2_integration.customer]
}
run "reject_other_vpc" {
  command = plan
  variables {
    authentication = {
      contract_version = 1
      environment      = "staging"
      aws_region       = "us-east-1"
      alias_arn        = "arn:aws:lambda:us-east-1:123456789012:function:oficina-staging-autenticacao:live"
      issuer           = "https://abc123.execute-api.us-east-1.amazonaws.com"
      audience         = "oficina-api"
    }
    jwt_ready = true
    customer_backend = {
      vpc_id                = "vpc-0123456789abcdef0"
      vpc_link_id           = "vpc123"
      listener_arn          = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/oficina/0123456789abcdef/0123456789abcdef"
      server_name_to_verify = "api.internal.example.com"
    }
  }
  override_data {
    target = data.aws_lb.customer[0]
    values = { internal = true, load_balancer_type = "application", vpc_id = "vpc-0123456789abcdef9" }
  }
  expect_failures = [aws_apigatewayv2_integration.customer]
}
run "reject_https_without_hostname_validation" {
  command = plan
  variables {
    authentication = {
      contract_version = 1
      environment      = "staging"
      aws_region       = "us-east-1"
      alias_arn        = "arn:aws:lambda:us-east-1:123456789012:function:oficina-staging-autenticacao:live"
      issuer           = "https://abc123.execute-api.us-east-1.amazonaws.com"
      audience         = "oficina-api"
    }
    jwt_ready = true
    customer_backend = {
      vpc_id                = "vpc-0123456789abcdef0"
      vpc_link_id           = "vpc123"
      listener_arn          = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/oficina/0123456789abcdef/0123456789abcdef"
      server_name_to_verify = null
    }
  }
  expect_failures = [aws_apigatewayv2_integration.customer]
}
run "reject_disabled_throttling" {
  command = plan
  variables { throttling = { rate = 5, burst = 10, auth_rate = 0, auth_burst = 2 } }
  expect_failures = [var.throttling]
}
