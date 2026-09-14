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
    error_message = "Ambiente deve ser staging ou producao."
  }
}
variable "aws_account_id" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Informe a conta de 12 digitos."
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
variable "jwt_audience" {
  type    = string
  default = "oficina-api"
  validation {
    condition     = length(trimspace(var.jwt_audience)) > 0 && length(var.jwt_audience) <= 200
    error_message = "Audiencia deve ter de 1 a 200 caracteres."
  }
}
variable "authentication" {
  description = "Campos do output authentication do Oficina-serverless. null cria apenas a URL inicial, sem rotas."
  type = object({
    contract_version = number
    environment      = string
    aws_region       = string
    alias_arn        = string
    issuer           = string
    audience         = string
  })
  default = null
  validation {
    condition = var.authentication == null ? true : (
      var.authentication.contract_version == 1 &&
      var.authentication.environment == var.environment &&
      var.authentication.aws_region == var.aws_region &&
      var.authentication.audience == var.jwt_audience &&
      var.authentication.alias_arn == "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${var.project_name}-${var.environment}-autenticacao:live"
    )
    error_message = "Use o contrato v1 e alias live da autenticacao deste projeto, ambiente, conta e regiao, com a mesma audiencia."
  }
}
variable "jwt_ready" {
  description = "Habilitar somente depois de verificar discovery/JWKS HTTPS no Gateway; evita ciclo de bootstrap."
  type        = bool
  default     = false
  validation {
    condition     = !var.jwt_ready || var.authentication != null
    error_message = "JWT exige a integracao de autenticacao configurada."
  }
}
variable "customer_backend" {
  description = "VPC Link e listener ALB interno da API, preparados na etapa de deploy EKS."
  type = object({
    vpc_id                = string
    vpc_link_id           = string
    listener_arn          = string
    server_name_to_verify = optional(string)
  })
  default = null
  validation {
    condition = var.customer_backend == null ? true : (
      var.jwt_ready &&
      can(regex("^vpc-[0-9a-f]{8}([0-9a-f]{9})?$", var.customer_backend.vpc_id)) &&
      can(regex("^[a-z0-9]+$", var.customer_backend.vpc_link_id)) &&
      can(regex("^arn:aws:elasticloadbalancing:${var.aws_region}:${var.aws_account_id}:listener/app/[a-zA-Z0-9-]+/[a-z0-9]+/[a-z0-9]+$", var.customer_backend.listener_arn)) &&
      (var.customer_backend.server_name_to_verify == null ? true :
      can(regex("^[a-zA-Z0-9][a-zA-Z0-9.-]+$", var.customer_backend.server_name_to_verify)))
    )
    error_message = "Backend exige JWT pronto, VPC Link e listener ALB da mesma conta/regiao; nome TLS deve ser somente hostname."
  }
}
variable "throttling" {
  description = "Limites agregados por rota; nao substituem protecao por CPF/IP."
  type = object({
    rate       = number
    burst      = number
    auth_rate  = number
    auth_burst = number
  })
  default = { rate = 5, burst = 10, auth_rate = 1, auth_burst = 2 }
  validation {
    condition = (
      var.throttling.rate >= 1 && var.throttling.rate <= 50 &&
      var.throttling.burst >= 1 && var.throttling.burst <= 100 &&
      var.throttling.auth_rate >= 0.1 && var.throttling.auth_rate <= var.throttling.rate &&
      var.throttling.auth_burst >= 1 && var.throttling.auth_burst <= var.throttling.burst &&
      floor(var.throttling.burst) == var.throttling.burst &&
      floor(var.throttling.auth_burst) == var.throttling.auth_burst
    )
    error_message = "Use rate 1..50, burst inteiro 1..100; autenticacao deve ter limites positivos iguais ou menores."
  }
}
