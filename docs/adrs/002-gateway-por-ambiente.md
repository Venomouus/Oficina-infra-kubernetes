# ADR 002 — HTTP API separado por ambiente

Status: implementado em Terraform e testes.

Criar um HTTP API por ambiente no root gateway/, usando states separados de
staging/producao. A fundacao VPC/EKS continua no root infra/ e state compartilhado.

Usar a URL HTTPS gerenciada do Gateway como issuer publico da Lambda, stage
$default e integracao HTTP API v2 com o alias live. Publicar autenticacao,
discovery e JWKS antes de habilitar o authorizer JWT; o marcador jwt_ready
separa essas fases sem depender de terraform -target.

Apenas quatro rotas de cliente usam o authorizer e scope oficina:cliente.
A API mantém a verificacao de cliente ativo e propriedade da OS. Rotas
administrativas HS256 nao sao publicadas por um proxy generico neste PR.

O root aceita um backend privado existente por VPC Link e listener ALB interno;
nao cria esses componentes antes da etapa EKS/aplicacao. A consulta do listener
e ALB valida privacidade, VPC e configuracao TLS. Nomes de dominio/certificados
do listener serao definidos junto com o backend.

Throttling agregado reduz carga, mas nao equivale a limitacao por identidade.
Logs de acesso possuem apenas metadados operacionais e retencao de sete dias.
O HTTP API externo usa HTTPS; listener HTTP interno nao oferece TLS nesse trecho.

Consequencias: states e URLs separados reduzem mistura de ambientes, mas exigem
coordenar contratos e permissao de invocacao com o serverless. Bootstrap SQL,
Gateway em funcionamento, ALB/VPC Link, CD e evidencias reais continuam pendentes.

[Runbook, contratos e fontes](../../gateway/README.md).
