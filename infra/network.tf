resource "aws_vpc" "platform" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = local.platform_name }

  lifecycle {
    precondition {
      condition     = alltrue([for zone in var.availability_zones : startswith(zone, var.aws_region) && length(zone) == length(var.aws_region) + 1])
      error_message = "Todas as zonas devem pertencer a aws_region."
    }
  }
}

resource "aws_default_security_group" "closed" {
  vpc_id = aws_vpc.platform.id
  # O SG default nao autoriza entrada nem saida.
  tags = { Name = "${local.platform_name}-default-closed" }
}

resource "aws_internet_gateway" "platform" {
  vpc_id = aws_vpc.platform.id
  tags   = { Name = local.platform_name }
}

resource "aws_subnet" "public" {
  for_each                = local.zones
  vpc_id                  = aws_vpc.platform.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, each.value)
  map_public_ip_on_launch = false
  tags = {
    Name                     = "${local.platform_name}-public-${each.key}"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "database" {
  for_each                = local.zones
  vpc_id                  = aws_vpc.platform.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, each.value + 4)
  map_public_ip_on_launch = false
  tags                    = { Name = "${local.platform_name}-database-${each.key}" }
}

resource "aws_subnet" "private" {
  for_each                = local.zones
  vpc_id                  = aws_vpc.platform.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, each.value + 8)
  map_public_ip_on_launch = false
  tags = {
    Name                              = "${local.platform_name}-private-${each.key}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.platform.id
  tags   = { Name = "${local.platform_name}-public" }
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.platform.id
}

resource "aws_route_table_association" "public" {
  for_each       = local.zones
  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  for_each = local.nat_zones
  domain   = "vpc"
  tags     = { Name = "${local.platform_name}-nat-${each.key}" }
}

resource "aws_nat_gateway" "platform" {
  for_each      = local.nat_zones
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id
  depends_on    = [aws_internet_gateway.platform]
  tags          = { Name = "${local.platform_name}-nat-${each.key}" }
}

resource "aws_route_table" "private" {
  for_each = local.zones
  vpc_id   = aws_vpc.platform.id
  tags     = { Name = "${local.platform_name}-private-${each.key}" }
}

resource "aws_route" "private_egress" {
  for_each               = local.zones
  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.platform[var.nat_mode == "per_az" ? each.key : var.availability_zones[0]].id
}

resource "aws_route_table_association" "private" {
  for_each       = local.zones
  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

# Banco isolado: apenas rota local da VPC, sem NAT/Internet Gateway.
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.platform.id
  tags   = { Name = "${local.platform_name}-database-isolated" }
}

resource "aws_route_table_association" "database" {
  for_each       = local.zones
  subnet_id      = aws_subnet.database[each.key].id
  route_table_id = aws_route_table.database.id
}

# Endpoint de gateway S3, usado por downloads das camadas de imagens do ECR.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.platform.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for table in aws_route_table.private : table.id]
  tags              = { Name = "${local.platform_name}-s3" }
}

# SG de origem das Lambdas, um por ambiente. Regras para PostgreSQL pertencem
# ao repo database e usarao recursos de regra separados, sem regras inline aqui.
resource "aws_security_group" "lambda" {
  for_each    = var.environments
  name        = "${local.platform_name}-lambda-${each.key}"
  description = "Identidade de rede das Lambdas de ${each.key}"
  vpc_id      = aws_vpc.platform.id
}

resource "aws_vpc_security_group_egress_rule" "lambda_https" {
  for_each          = var.environments
  security_group_id = aws_security_group.lambda[each.key].id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
  description       = "HTTPS de saida via NAT para APIs AWS"
}
