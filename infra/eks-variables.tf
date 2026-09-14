variable "aws_account_id" {
  description = "Conta autorizada para provisionamento; o provider rejeita outra conta."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Informe o ID AWS com 12 digitos."
  }
}

variable "cluster_admin_principal_arns" {
  description = "Roles/usuarios IAM explicitamente autorizados a administrar o cluster. Nao usar ARN STS de sessao."
  type        = set(string)
  validation {
    condition = length(var.cluster_admin_principal_arns) >= 1 && alltrue([
      for arn in var.cluster_admin_principal_arns :
      can(regex("^arn:aws:iam::${var.aws_account_id}:(role|user)/[A-Za-z0-9_+=,.@/-]+$", arn))
    ])
    error_message = "Informe pelo menos um ARN IAM de role/usuario da conta autorizada."
  }
}

variable "kubernetes_version" {
  description = "Versao EKS em suporte padrao; confirmar disponibilidade antes de aplicar."
  type        = string
  default     = "1.35"
  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "Use uma versao Kubernetes como 1.35."
  }
}

variable "node_instance_type" {
  description = "Tipo EC2 x86_64 compativel com AL2023; dimensionar no plan da conta."
  type        = string
  default     = "t3.medium"
  validation {
    condition     = contains(["t3.medium", "t3.large", "m6i.large", "m6a.large"], var.node_instance_type)
    error_message = "Use um dos tipos x86_64 previstos para o laboratorio."
  }
}

variable "node_scaling" {
  description = "Capacidade do managed node group. Limites nao instalam um autoscaler."
  type        = object({ min = number, desired = number, max = number })
  default     = { min = 2, desired = 2, max = 3 }
  validation {
    condition = (
      var.node_scaling.min >= 2 &&
      var.node_scaling.min <= var.node_scaling.desired &&
      var.node_scaling.desired <= var.node_scaling.max &&
      var.node_scaling.max <= 6 &&
      alltrue([for size in values(var.node_scaling) : floor(size) == size])
    )
    error_message = "Use inteiros com 2 <= min <= desired <= max <= 6."
  }
}

variable "nat_mode" {
  description = "single reduz NATs no laboratorio; per_az mantem saida em cada zona."
  type        = string
  default     = "single"
  validation {
    condition     = contains(["single", "per_az"], var.nat_mode)
    error_message = "Use single ou per_az."
  }
}

variable "eks_public_access_cidrs" {
  description = "Lista vazia mantem EKS privado. Opcional: redes administrativas IPv4 restritas (/24 a /32)."
  type        = list(string)
  default     = []
  validation {
    condition = length(var.eks_public_access_cidrs) <= 8 && alltrue([
      for cidr in var.eks_public_access_cidrs :
      can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) >= 24, false)
    ])
    error_message = "Use no maximo oito CIDRs IPv4 de /24 a /32; 0.0.0.0/0 nao e permitido."
  }
}

variable "log_retention_days" {
  description = "Retencao de logs do control plane; nao substitui observabilidade da aplicacao."
  type        = number
  default     = 7
  validation {
    condition     = contains([7, 14, 30, 60, 90], var.log_retention_days)
    error_message = "Use 7, 14, 30, 60 ou 90 dias."
  }
}

variable "addon_versions" {
  description = "Overrides de versoes compativeis retornadas pela AWS. null usa a versao default compativel."
  type = object({
    vpc-cni        = optional(string)
    kube-proxy     = optional(string)
    coredns        = optional(string)
    metrics-server = optional(string)
  })
  default = {}
  validation {
    condition = alltrue([
      for version in values(var.addon_versions) :
      version == null ? true : can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", version))
    ])
    error_message = "Use versoes no formato vX.Y.Z-eksbuild.N ou null."
  }
}
