variable "project_name" {
  description = "Prefixo da plataforma compartilhada de laboratorio."
  type        = string
  default     = "oficina"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,29}$", var.project_name))
    error_message = "Use de 2 a 30 caracteres: letras minusculas, numeros e hifens, iniciando com letra."
  }
}

variable "aws_region" {
  description = "Regiao planejada; confirme disponibilidade e custo antes do provisionamento."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region))
    error_message = "Informe uma regiao AWS no formato us-east-1."
  }
}

variable "availability_zones" {
  description = "Duas ou tres zonas da regiao escolhida, a verificar na conta antes do deploy."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition = (
      length(var.availability_zones) >= 2 &&
      length(var.availability_zones) <= 3 &&
      length(distinct(var.availability_zones)) == length(var.availability_zones) &&
      alltrue([for zone in var.availability_zones : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+[a-z]$", zone))])
    )
    error_message = "Informe duas ou tres zonas AWS distintas, como us-east-1a e us-east-1b."
  }
}

variable "vpc_cidr" {
  description = "CIDR IPv4 planejado para a rede do laboratorio, com prefixo entre /16 e /20."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition = can(cidrnetmask(var.vpc_cidr)) && try(
      tonumber(split("/", var.vpc_cidr)[1]) >= 16 &&
      tonumber(split("/", var.vpc_cidr)[1]) <= 20,
      false
    )
    error_message = "Informe um CIDR IPv4 valido com prefixo entre /16 e /20."
  }
}

variable "environments" {
  description = "Ambientes logicos da mesma plataforma; nao representam dois clusters EKS."
  type = map(object({
    branch    = string
    namespace = string
  }))
  default = {
    staging = {
      branch    = "develop"
      namespace = "oficina-staging"
    }
    producao = {
      branch    = "master"
      namespace = "oficina-producao"
    }
  }

  validation {
    condition = (
      toset(keys(var.environments)) == toset(["staging", "producao"]) &&
      try(var.environments["staging"].branch == "develop", false) &&
      try(var.environments["producao"].branch == "master", false) &&
      length(distinct([for environment in values(var.environments) : environment.namespace])) == 2 &&
      alltrue([
        for environment in values(var.environments) :
        length(environment.namespace) <= 63 &&
        can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", environment.namespace))
      ])
    )
    error_message = "Configure staging/develop e producao/master, com namespaces Kubernetes validos e distintos."
  }
}
