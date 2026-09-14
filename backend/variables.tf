variable "project_name" {
  type    = string
  default = "oficina"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,29}$", var.project_name))
    error_message = "Use prefixo de 2 a 30 caracteres minusculos, numeros e hifens."
  }
}
variable "environment" {
  type    = string
  default = "staging"
  validation {
    condition     = contains(["staging", "producao"], var.environment)
    error_message = "Use staging ou producao."
  }
}
variable "aws_account_id" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Informe a conta AWS com 12 digitos."
  }
}
variable "aws_region" {
  type    = string
  default = "us-east-1"
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region))
    error_message = "Informe uma regiao AWS valida."
  }
}
variable "platform" {
  description = "Campos do output platform do root infra/. IDs reais do mesmo cluster e conta."
  type = object({
    contract_version              = number
    aws_region                    = string
    vpc_id                        = string
    cluster_name                  = string
    private_subnet_ids            = set(string)
    application_security_group_id = string
    environments                  = map(object({ branch = string, namespace = string }))
  })
  validation {
    condition = (
      var.platform.contract_version == 1 && var.platform.aws_region == var.aws_region &&
      can(regex("^vpc-([0-9a-f]{8}|[0-9a-f]{17})$", var.platform.vpc_id)) &&
      can(regex("^sg-([0-9a-f]{8}|[0-9a-f]{17})$", var.platform.application_security_group_id)) &&
      length(var.platform.private_subnet_ids) >= 2 &&
      alltrue([for id in var.platform.private_subnet_ids : can(regex("^subnet-([0-9a-f]{8}|[0-9a-f]{17})$", id))]) &&
      try(var.platform.environments[var.environment].branch == (var.environment == "staging" ? "develop" : "master"), false) &&
      try(can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", var.platform.environments[var.environment].namespace)), false) &&
      length(distinct([for env in values(var.platform.environments) : env.namespace])) == length(var.platform.environments)
    )
    error_message = "Contrato v1 deve corresponder a regiao, conter VPC/SG/subnets validos e namespaces exclusivos com branch correta."
  }
}
variable "listener_tls" {
  description = "null usa HTTP privado. HTTPS exige certificado ACM e hostname que ele cobre, na mesma conta/regiao."
  type        = object({ certificate_arn = string, server_name_to_verify = string })
  default     = null
  validation {
    condition = var.listener_tls == null ? true : (
      can(regex("^arn:aws:acm:${var.aws_region}:${var.aws_account_id}:certificate/[0-9a-f-]{36}$", var.listener_tls.certificate_arn)) &&
      can(regex("^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$", var.listener_tls.server_name_to_verify))
    )
    error_message = "HTTPS requer ARN ACM da conta/regiao e hostname DNS sem protocolo, caminho ou wildcard."
  }
}
variable "allow_destroy" {
  description = "Desativa protecao de exclusao do ALB. Aplicar explicitamente antes de destruir o laboratorio."
  type        = bool
  default     = false
}
