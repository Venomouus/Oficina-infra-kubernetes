locals {
  platform_name = "${var.project_name}-lab"
  cluster_name  = "${local.platform_name}-eks"
  zones         = { for index, zone in var.availability_zones : zone => index }
  nat_zones     = var.nat_mode == "per_az" ? local.zones : { (var.availability_zones[0]) = 0 }
  tags = {
    Project     = var.project_name
    Environment = "shared-lab"
    ManagedBy   = "terraform"
    Repository  = "Oficina-infra-kubernetes"
  }
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]
  default_tags { tags = local.tags }
}

data "aws_partition" "current" {}
