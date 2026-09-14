# Regras separadas: Terraform e o unico dono da conectividade deste backend.
resource "aws_security_group" "vpc_link" {
  name_prefix = "${local.name}-link-"
  description = "VPC Link to private API listener only"
  vpc_id      = var.platform.vpc_id
}
resource "aws_security_group" "alb" {
  name_prefix = "${local.name}-alb-"
  description = "Private API ALB reached only by its VPC Link"
  vpc_id      = var.platform.vpc_id
}
resource "aws_vpc_security_group_egress_rule" "link_to_alb" {
  security_group_id            = aws_security_group.vpc_link.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = local.listener_port
  to_port                      = local.listener_port
}
resource "aws_vpc_security_group_ingress_rule" "alb_from_link" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.vpc_link.id
  ip_protocol                  = "tcp"
  from_port                    = local.listener_port
  to_port                      = local.listener_port
}
resource "aws_vpc_security_group_egress_rule" "alb_to_api" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = var.platform.application_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}
resource "aws_vpc_security_group_ingress_rule" "api_from_alb" {
  security_group_id            = var.platform.application_security_group_id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}
