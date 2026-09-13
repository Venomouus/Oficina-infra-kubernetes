output "planned_network" {
  description = "Planejamento de CIDRs; nao sao subnets nem VPC existentes."
  value       = local.planned_network
}

output "planned_platform" {
  description = "Nomes e ambientes planejados; nao sao IDs, URLs ou recursos AWS existentes."
  value       = local.planned_platform
}
