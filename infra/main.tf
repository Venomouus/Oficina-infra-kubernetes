# Base declarativa do laboratorio. Nao existem provider AWS nem recursos neste PR.
# Estes valores serao usados na implementacao de rede, EKS e API Gateway.
locals {
  platform_name = "${var.project_name}-lab"

  planned_network = {
    region   = var.aws_region
    vpc_cidr = var.vpc_cidr
    subnets = [
      for index, zone in var.availability_zones : {
        availability_zone = zone
        public_cidr       = cidrsubnet(var.vpc_cidr, 4, index)
        private_cidr      = cidrsubnet(var.vpc_cidr, 4, index + 8)
      }
    ]
  }

  planned_platform = {
    cluster_name     = "${local.platform_name}-eks"
    api_gateway_name = "${local.platform_name}-gateway"
    environments     = var.environments
  }
}
