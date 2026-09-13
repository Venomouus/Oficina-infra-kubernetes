# Validacao Terraform

Esta pasta contem variaveis validadas, calculo de CIDRs e nomes planejados.
Ainda nao declara recursos AWS, providers, backend remoto ou namespaces reais.

## Comandos locais

Na raiz do repositorio:

```powershell
terraform -chdir=infra fmt -check -recursive
terraform -chdir=infra init -backend=false -input=false
terraform -chdir=infra validate
```

Terraform >= 1.6 e < 2.0 e necessario; a pipeline usa 1.15.8.

[O validate verifica consistencia da configuracao](https://developer.hashicorp.com/terraform/cli/commands/validate);
nao comprova disponibilidade de zonas, permissoes, quotas ou funcionamento na AWS.

## Configuracao de exemplo

`terraform.tfvars.example` inclui staging e producao na mesma plataforma.
Para experimentar configuracoes locais, copie para `terraform.tfvars`, ignorado
pelo Git. O CI valida a estrutura e os valores padrao; ele nao carrega o arquivo
de exemplo nem confirma um plano real de provisionamento.

Confirme regiao e zonas na conta antes de usar a configuracao na nuvem.
Os nomes de zonas do exemplo sao configuracoes propostas, nao uma descoberta
dos recursos disponiveis na sua conta.

## Estado e ownership futuros

- Rede, cluster e componentes compartilhados devem ter um unico estado Terraform.
- Recursos especificos de staging e producao terao ownership e estados separados.
- Nenhum recurso compartilhado deve ser gerenciado por dois estados.
- As pipelines devem serializar alteracoes no mesmo estado, com locking remoto.
- PRs da infraestrutura compartilhada devem ser validados antes de aplicar mudancas
  que afetem os dois ambientes. A politica de promocao desse estado deve ser
  definida junto ao CD; nao basta executar o mesmo root em dois estados.
- Backend remoto, OIDC, plan e apply ainda serao implementados.

## Proximas implementacoes

1. Provider AWS e rede: VPC, subnets, rotas, saida e regras de acesso.
2. EKS: IAM, nos, acesso administrativo e distribuicao entre zonas.
3. Componentes: metrics-server, escalabilidade de nos e balanceador interno.
4. API Gateway e VPC Link, integrados aos destinos e autorizador JWT.
5. Namespaces, politicas de acesso e monitoramento.
6. Validacao real de plan e deploy automatico controlado por DEPLOY_ENABLED.

Nao execute apply para tentar subir a AWS com esta base: ainda nao ha
recursos provisionaveis. Nenhum comando de provisionamento foi executado neste PR.
