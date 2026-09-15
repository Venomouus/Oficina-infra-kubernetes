variable "academy_role_arn" {
  description = "Somente Academy: role preexistente. null preserva IAM/IRSA proprios."
  type        = string
  default     = null
  validation {
    condition     = var.academy_role_arn == null ? true : can(regex("^arn:aws:iam::${var.aws_account_id}:role/[A-Za-z0-9_+=,.@/-]+$", var.academy_role_arn))
    error_message = "A role Academy deve pertencer a conta configurada."
  }
}

moved {
  from = aws_iam_role.cluster
  to   = aws_iam_role.cluster[0]
}
moved {
  from = aws_iam_role_policy_attachment.cluster
  to   = aws_iam_role_policy_attachment.cluster[0]
}
moved {
  from = aws_iam_openid_connect_provider.cluster
  to   = aws_iam_openid_connect_provider.cluster[0]
}
moved {
  from = aws_iam_role.vpc_cni
  to   = aws_iam_role.vpc_cni[0]
}
moved {
  from = aws_iam_role_policy_attachment.vpc_cni
  to   = aws_iam_role_policy_attachment.vpc_cni[0]
}
moved {
  from = aws_iam_role.nodes
  to   = aws_iam_role.nodes[0]
}
moved {
  from = aws_iam_role.load_balancer_controller
  to   = aws_iam_role.load_balancer_controller[0]
}
moved {
  from = aws_iam_role_policy.target_registration
  to   = aws_iam_role_policy.target_registration[0]
}
