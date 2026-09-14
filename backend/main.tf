locals {
  # Limite de 32 caracteres para ALB/TG; hash evita colisoes por truncamento.
  name          = "${substr(var.project_name, 0, 12)}-${var.environment}-${substr(sha256(var.project_name), 0, 6)}"
  namespace     = var.platform.environments[var.environment].namespace
  listener_port = var.listener_tls == null ? 80 : 443
}

data "aws_subnet" "private" {
  for_each = var.platform.private_subnet_ids
  id       = each.value
}
data "aws_route_table" "private" {
  for_each = var.platform.private_subnet_ids
  filter {
    name   = "association.subnet-id"
    values = [each.value]
  }
}
data "aws_eks_cluster" "platform" {
  name = var.platform.cluster_name
}

resource "aws_lb" "api" {
  name                       = local.name
  internal                   = true
  load_balancer_type         = "application"
  ip_address_type            = "ipv4"
  subnets                    = var.platform.private_subnet_ids
  security_groups            = [aws_security_group.alb.id]
  enable_deletion_protection = !var.allow_destroy
  drop_invalid_header_fields = true
  desync_mitigation_mode     = "defensive"
  lifecycle {
    precondition {
      condition = (
        alltrue([for subnet in data.aws_subnet.private :
          subnet.vpc_id == var.platform.vpc_id && !subnet.map_public_ip_on_launch
        ]) &&
        length(distinct([for subnet in data.aws_subnet.private : subnet.availability_zone])) >= 2 &&
        alltrue(flatten([for table in data.aws_route_table.private :
          [for route in table.routes : !startswith(coalesce(route.gateway_id, "none"), "igw-")]
        ])) &&
        data.aws_eks_cluster.platform.vpc_config[0].vpc_id == var.platform.vpc_id &&
        data.aws_eks_cluster.platform.vpc_config[0].cluster_security_group_id == var.platform.application_security_group_id
      )
      error_message = "ALB exige subnets privadas em pelo menos duas AZs, sem rota IGW, na VPC/SG do EKS informado."
    }
  }
}
resource "aws_lb_target_group" "api" {
  name                 = local.name
  vpc_id               = var.platform.vpc_id
  target_type          = "ip"
  protocol             = "HTTP"
  port                 = 8080
  deregistration_delay = 30
  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}
resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.api.arn
  port              = local.listener_port
  protocol          = var.listener_tls == null ? "HTTP" : "HTTPS"
  certificate_arn   = var.listener_tls == null ? null : var.listener_tls.certificate_arn
  ssl_policy        = var.listener_tls == null ? null : "ELBSecurityPolicy-TLS13-1-2-2021-06"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}
resource "aws_apigatewayv2_vpc_link" "api" {
  name               = "${var.project_name}-${var.environment}-api"
  subnet_ids         = var.platform.private_subnet_ids
  security_group_ids = [aws_security_group.vpc_link.id]
}
