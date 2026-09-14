# Todos os providers sao mockados: nenhum run provisiona recursos reais.
mock_provider "aws" {
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-0123456789abcdef0", latest_version = 1 }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_eks_addon_version" {
    defaults = { version = "v1.0.0-eksbuild.1" }
  }
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-1:123456789012:cluster/oficina-lab-eks"
      endpoint              = "https://eks.example.test"
      certificate_authority = [{ data = "dGVzdA==" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/TEST" }] }]
    }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/test-role" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/TEST" }
  }
}

variables {
  aws_account_id               = "123456789012"
  cluster_admin_principal_arns = ["arn:aws:iam::123456789012:role/OficinaPlatformAdmin"]
}

run "private_platform_and_integration_contract" {
  command = apply
  assert {
    condition = (
      length(aws_subnet.private) == 2 && length(aws_subnet.database) == 2 &&
      alltrue([for subnet in aws_subnet.private : !subnet.map_public_ip_on_launch]) &&
      alltrue([for subnet in aws_subnet.database : !subnet.map_public_ip_on_launch]) &&
      length(distinct(concat(
        [for subnet in aws_subnet.public : subnet.cidr_block],
        [for subnet in aws_subnet.private : subnet.cidr_block],
        [for subnet in aws_subnet.database : subnet.cidr_block]
      ))) == 6
    )
    error_message = "Subnets de workloads/banco devem ser privadas, distribuidas e nao sobrepostas."
  }
  assert {
    condition = (
      length(aws_nat_gateway.platform) == 1 &&
      alltrue([for route in aws_route.private_egress : route.nat_gateway_id == aws_nat_gateway.platform["us-east-1a"].id]) &&
      alltrue([for association in aws_route_table_association.database : association.route_table_id == aws_route_table.database.id]) &&
      aws_route.internet.route_table_id != aws_route_table.database.id &&
      alltrue([for route in aws_route.private_egress : route.route_table_id != aws_route_table.database.id])
    )
    error_message = "No modo single, workloads usam um NAT; banco nunca recebe rota de internet."
  }
  assert {
    condition = (
      aws_eks_cluster.platform.vpc_config[0].endpoint_private_access &&
      !aws_eks_cluster.platform.vpc_config[0].endpoint_public_access &&
      !aws_eks_cluster.platform.access_config[0].bootstrap_cluster_creator_admin_permissions &&
      aws_eks_cluster.platform.access_config[0].authentication_mode == "API" &&
      length(aws_eks_access_entry.administrator) == 1
    )
    error_message = "EKS deve iniciar privado e sem acesso administrador implicito."
  }
  assert {
    condition = (
      toset(aws_eks_node_group.workers.subnet_ids) == toset([for subnet in aws_subnet.private : subnet.id]) &&
      aws_eks_node_group.workers.scaling_config[0].min_size >= 2 &&
      aws_launch_template.nodes.metadata_options[0].http_tokens == "required" &&
      aws_launch_template.nodes.metadata_options[0].http_put_response_hop_limit == 1 &&
      alltrue([for mapping in aws_launch_template.nodes.block_device_mappings : mapping.ebs[0].encrypted])
    )
    error_message = "Workers devem usar subnets privadas, IMDSv2 e disco criptografado."
  }
  assert {
    condition = (
      output.platform.contract_version == 1 &&
      length(output.platform.database_subnet_ids) == 2 &&
      toset(keys(output.platform.lambda_security_group_ids)) == toset(["staging", "producao"]) &&
      output.platform.environments.staging.branch == "develop" &&
      output.platform.environments.producao.branch == "master" &&
      output.platform.environments.staging.namespace != output.platform.environments.producao.namespace
    )
    error_message = "Contrato deve fornecer redes e identidades para os dois ambientes."
  }
  assert {
    condition = (
      length(aws_eks_cluster.platform.enabled_cluster_log_types) == 5 &&
      aws_cloudwatch_log_group.cluster.retention_in_days == 7 &&
      aws_eks_addon.runtime["metrics-server"].addon_name == "metrics-server" &&
      jsondecode(aws_eks_addon.vpc_cni.configuration_values).enableNetworkPolicy == "true" &&
      !contains(keys(aws_iam_role_policy_attachment.nodes), "AmazonEKS_CNI_Policy")
    )
    error_message = "Logs, metricas e CNI com IAM separado devem estar preparados."
  }
}

run "three_zones_with_independent_egress" {
  command = apply
  variables {
    availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
    nat_mode           = "per_az"
  }
  assert {
    condition = length(aws_nat_gateway.platform) == 3 && alltrue([
      for zone, route in aws_route.private_egress : route.nat_gateway_id == aws_nat_gateway.platform[zone].id
    ])
    error_message = "per_az deve utilizar um NAT da propria zona."
  }
}

run "restricted_public_endpoint" {
  command = plan
  variables { eks_public_access_cidrs = ["203.0.113.10/32"] }
  assert {
    condition = (aws_eks_cluster.platform.vpc_config[0].endpoint_public_access &&
      aws_eks_cluster.platform.vpc_config[0].endpoint_private_access &&
    toset(aws_eks_cluster.platform.vpc_config[0].public_access_cidrs) == toset(["203.0.113.10/32"]))
    error_message = "Acesso publico opcional deve conservar acesso privado e CIDR restrito."
  }
}

run "reject_world_access" {
  command = plan
  variables { eks_public_access_cidrs = ["0.0.0.0/0"] }
  expect_failures = [var.eks_public_access_cidrs]
}

run "reject_missing_administrator" {
  command = plan
  variables { cluster_admin_principal_arns = [] }
  expect_failures = [var.cluster_admin_principal_arns]
}

run "reject_cross_account_administrator" {
  command = plan
  variables { cluster_admin_principal_arns = ["arn:aws:iam::999999999999:role/Administrator"] }
  expect_failures = [var.cluster_admin_principal_arns]
}

run "reject_inconsistent_scaling" {
  command = plan
  variables { node_scaling = { min = 2, desired = 4, max = 3 } }
  expect_failures = [var.node_scaling]
}

run "reject_zone_in_another_region" {
  command = plan
  variables { availability_zones = ["us-west-2a", "us-west-2b"] }
  expect_failures = [aws_vpc.platform]
}
