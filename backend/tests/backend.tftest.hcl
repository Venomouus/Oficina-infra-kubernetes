# Provider inteiramente simulado: nenhum recurso real, credencial ou backend remoto.
mock_provider "aws" {
  mock_data "aws_subnet" {
    defaults = {
      vpc_id                  = "vpc-0123456789abcdef0"
      availability_zone       = "us-east-1a"
      map_public_ip_on_launch = false
    }
  }
  mock_data "aws_route_table" {
    defaults = { routes = [] }
  }
  mock_data "aws_eks_cluster" {
    defaults = {
      vpc_config = [{
        vpc_id                    = "vpc-0123456789abcdef0"
        cluster_security_group_id = "sg-0123456789abcdef0"
      }]
    }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/oficina/0123456789abcdef" }
  }
  mock_resource "aws_lb_listener" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/oficina/0123456789abcdef/0123456789abcdef" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/oficina/0123456789abcdef" }
  }
  mock_resource "aws_security_group" {
    defaults = { id = "sg-0123456789abcdef1" }
  }
  mock_resource "aws_apigatewayv2_vpc_link" {
    defaults = { id = "vpc123" }
  }
}
override_data {
  target = data.aws_subnet.private["subnet-0123456789abcdef1"]
  values = {
    vpc_id                  = "vpc-0123456789abcdef0"
    availability_zone       = "us-east-1b"
    map_public_ip_on_launch = false
  }
}
variables {
  aws_account_id = "123456789012"
  platform = {
    contract_version              = 1
    aws_region                    = "us-east-1"
    vpc_id                        = "vpc-0123456789abcdef0"
    cluster_name                  = "oficina-lab-eks"
    private_subnet_ids            = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
    application_security_group_id = "sg-0123456789abcdef0"
    environments = {
      staging  = { branch = "develop", namespace = "oficina-staging" }
      producao = { branch = "master", namespace = "oficina-producao" }
    }
  }
}
run "private_network_and_gateway_contract" {
  command = apply
  assert {
    condition = (
      aws_lb.api.internal && aws_lb.api.load_balancer_type == "application" &&
      aws_lb.api.enable_deletion_protection && aws_lb.api.drop_invalid_header_fields &&
      aws_lb_listener.api.port == 80 && aws_lb_listener.api.protocol == "HTTP" &&
      aws_lb_listener.api.default_action[0].target_group_arn == aws_lb_target_group.api.arn &&
      toset(aws_lb.api.subnets) == var.platform.private_subnet_ids &&
      toset(aws_apigatewayv2_vpc_link.api.subnet_ids) == var.platform.private_subnet_ids &&
      toset(aws_lb.api.security_groups) == toset([aws_security_group.alb.id]) &&
      toset(aws_apigatewayv2_vpc_link.api.security_group_ids) == toset([aws_security_group.vpc_link.id])
    )
    error_message = "Entrada deve ser ALB interno protegido, nas subnets privadas e com SGs exclusivos."
  }
  assert {
    condition = (
      aws_vpc_security_group_egress_rule.link_to_alb.referenced_security_group_id == aws_security_group.alb.id &&
      aws_vpc_security_group_ingress_rule.alb_from_link.referenced_security_group_id == aws_security_group.vpc_link.id &&
      aws_vpc_security_group_ingress_rule.alb_from_link.from_port == 80 &&
      aws_vpc_security_group_egress_rule.link_to_alb.to_port == 80 &&
      aws_vpc_security_group_egress_rule.alb_to_api.referenced_security_group_id == var.platform.application_security_group_id &&
      aws_vpc_security_group_ingress_rule.api_from_alb.security_group_id == var.platform.application_security_group_id &&
      aws_vpc_security_group_ingress_rule.api_from_alb.referenced_security_group_id == aws_security_group.alb.id &&
      aws_vpc_security_group_egress_rule.alb_to_api.from_port == 8080 &&
      aws_vpc_security_group_ingress_rule.api_from_alb.to_port == 8080 &&
      aws_vpc_security_group_ingress_rule.alb_from_link.cidr_ipv4 == null &&
      aws_vpc_security_group_ingress_rule.api_from_alb.cidr_ipv4 == null
    )
    error_message = "Trafego deve seguir Link -> ALB -> pods, somente nas portas necessarias e por referencia a SG."
  }
  assert {
    condition = (
      output.customer_backend.vpc_id == var.platform.vpc_id &&
      output.customer_backend.vpc_link_id == aws_apigatewayv2_vpc_link.api.id &&
      output.customer_backend.listener_arn == aws_lb_listener.api.arn &&
      output.customer_backend.server_name_to_verify == null
    )
    error_message = "Contrato deve ser compativel com customer_backend do Gateway sem TLS ficticio."
  }
  assert {
    condition = (
      aws_lb_target_group.api.target_type == "ip" && aws_lb_target_group.api.port == 8080 &&
      aws_lb_target_group.api.health_check[0].path == "/health" &&
      aws_lb_target_group.api.health_check[0].matcher == "200" &&
      aws_lb_target_group.api.health_check[0].port == "traffic-port" &&
      yamldecode(split("---\n", output.kubernetes_manifest)[0]).spec.type == "ClusterIP" &&
      yamldecode(split("---\n", output.kubernetes_manifest)[0]).spec.selector.app == "oficina-api" &&
      yamldecode(split("---\n", output.kubernetes_manifest)[1]).spec.targetGroupARN == aws_lb_target_group.api.arn &&
      yamldecode(split("---\n", output.kubernetes_manifest)[1]).spec.serviceRef.port == 8080 &&
      yamldecode(split("---\n", output.kubernetes_manifest)[1]).metadata.namespace == "oficina-staging" &&
      !contains(keys(yamldecode(split("---\n", output.kubernetes_manifest)[1]).spec), "networking")
    )
    error_message = "TGB deve registrar pods da API pelo ClusterIP, health correto e sem gerenciar SGs."
  }
}
run "https_and_production" {
  command = apply
  variables {
    environment = "producao"
    listener_tls = {
      certificate_arn       = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
      server_name_to_verify = "api.example.test"
    }
  }
  assert {
    condition = (
      aws_lb_listener.api.protocol == "HTTPS" && aws_lb_listener.api.port == 443 &&
      aws_lb_listener.api.certificate_arn == var.listener_tls.certificate_arn &&
      output.customer_backend.server_name_to_verify == "api.example.test" &&
      aws_vpc_security_group_ingress_rule.alb_from_link.from_port == 443 &&
      aws_vpc_security_group_egress_rule.link_to_alb.to_port == 443 &&
      output.backend.namespace == "oficina-producao" &&
      yamldecode(split("---\n", output.kubernetes_manifest)[0]).metadata.namespace == "oficina-producao"
    )
    error_message = "Producao deve usar seu namespace e HTTPS deve ser consistente com o contrato e SGs."
  }
}
run "explicit_teardown" {
  command = plan
  variables { allow_destroy = true }
  assert {
    condition     = !aws_lb.api.enable_deletion_protection
    error_message = "Desmontagem exige desativar explicitamente a protecao."
  }
}
run "reject_public_subnet" {
  command = plan
  override_data {
    target = data.aws_subnet.private["subnet-0123456789abcdef0"]
    values = { vpc_id = "vpc-0123456789abcdef0", availability_zone = "us-east-1a", map_public_ip_on_launch = true }
  }
  expect_failures = [aws_lb.api]
}
run "reject_single_zone" {
  command = plan
  override_data {
    target = data.aws_subnet.private["subnet-0123456789abcdef0"]
    values = { vpc_id = "vpc-0123456789abcdef0", availability_zone = "us-east-1b", map_public_ip_on_launch = false }
  }
  expect_failures = [aws_lb.api]
}
run "reject_other_vpc" {
  command = plan
  override_data {
    target = data.aws_subnet.private["subnet-0123456789abcdef0"]
    values = { vpc_id = "vpc-99999999999999999", availability_zone = "us-east-1a", map_public_ip_on_launch = false }
  }
  expect_failures = [aws_lb.api]
}
run "reject_internet_gateway_route" {
  command = plan
  override_data {
    target = data.aws_route_table.private["subnet-0123456789abcdef0"]
    values = { routes = [{ cidr_block = "0.0.0.0/0", gateway_id = "igw-0123456789abcdef0" }] }
  }
  expect_failures = [aws_lb.api]
}
run "reject_other_cluster_security_group" {
  command = plan
  override_data {
    target = data.aws_eks_cluster.platform
    values = { vpc_config = [{ vpc_id = "vpc-0123456789abcdef0", cluster_security_group_id = "sg-99999999999999999" }] }
  }
  expect_failures = [aws_lb.api]
}
run "reject_wrong_region" {
  command = plan
  variables { aws_region = "us-west-2" }
  expect_failures = [var.platform]
}
run "reject_certificate_from_another_account" {
  command = plan
  variables {
    listener_tls = {
      certificate_arn       = "arn:aws:acm:us-east-1:999999999999:certificate/12345678-1234-1234-1234-123456789012"
      server_name_to_verify = "api.example.test"
    }
  }
  expect_failures = [var.listener_tls]
}
