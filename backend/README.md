# Backend privado da API

Root Terraform por ambiente. Cria VPC Link, ALB interno, listener, target group IP
e regras de rede. Exporta o contrato consumido por gateway/ e o manifesto
Service ClusterIP + TargetGroupBinding (TGB) para o EKS.

**Codigo preparado; nenhum recurso AWS foi criado. DEPLOY_ENABLED=false.**
O manifesto nao contem Deployment, imagem, segredos, migrations ou NetworkPolicy.
Esses itens pertencem a entrega de workloads da Oficina-Mecanica.

## Recursos e ownership

| Componente | Dono |
|---|---|
| VPC/EKS/subnets e IAM do controlador | infra/, estado compartilhado |
| VPC Link, ALB, listener, target group e suas regras de SG | backend/, estado por ambiente |
| Instalacao unica do controlador via Helm | administracao do cluster |
| Registro/remocao dinamica dos IPs dos pods no target group | controlador via TGB |
| Service/TGB gerados por output | administracao do backend; aplicar uma unica vez por ambiente e atualizar quando mudar TG |
| Deployment, probes e politicas de rede da API | Oficina-Mecanica |
| Rotas, JWT e integracao privada | gateway/, estado por ambiente |

Nao criar Ingress nem Service LoadBalancer para esse ALB. Nao usar attachments
estaticos de IPs no Terraform. Nao gerenciar o mesmo Service/TGB em outro state
ou manifest da API: o pipeline de workloads consome o contrato deste backend.

Fluxo: Gateway -> VPC Link -> ALB interno -> IPs dos pods na porta 8080.
Link so tem egress para o SG do ALB na porta do listener. ALB aceita somente o SG
do Link e sai para o SG dos nodes/pods em 8080. O SG compartilhado do EKS recebe
essa origem em 8080; nao constitui isolamento entre namespaces. NetworkPolicies
e RBAC ainda devem ser instalados. A API continua validando JWT/role/propriedade.

As subnets sao consultadas na AWS no plan autenticado: mesma VPC, duas AZs,
sem IPv4 publico automatico nem rota IGW. O SG informado deve ser o SG do cluster.
Nao se altera nenhuma rota da plataforma neste root.

Health check HTTP /health exige 200 em 8080. Esta e a porta/caminho da API atual.
Targets so ficam saudaveis quando a aplicacao e suas dependencias estiverem prontas.

## TLS

O padrao listener_tls=null usa HTTP em rede privada. O endpoint externo do Gateway
continua HTTPS. ALB -> pods tambem e HTTP; nao declarar criptografia ponta a ponta.

Opcionalmente, fornecer listener_tls com certificate_arn ACM e server_name_to_verify
coberto pelo certificado, mesma conta/regiao. O listener passa a HTTPS/443 com
TLS 1.2/1.3 e o contrato configura a verificacao do hostname no Gateway.
O Terraform valida formato/conta/regiao, mas a cobertura do nome pelo certificado
deve ser conferida antes do apply. Nao cria dominio nem certificado.

## Validacao local

Na raiz do repositorio:

```powershell
terraform -chdir=backend fmt -check -recursive
terraform -chdir=backend init -backend=false -input=false -lockfile=readonly
terraform -chdir=backend validate -no-color
terraform -chdir=backend test -no-color
```

Os testes usam AWS simulada: privacidade, SGs, contrato, TGB, TLS, ambiente,
desmontagem e rejeicao de rede/conta/regiao incorretas. Nao precisam de tfvars.

## Configuracao para o deploy futuro

1. Provisionar a fundacao e obter seu output platform.
2. Preencher terraform.tfvars a partir do exemplo; usar IDs reais e o ambiente.
3. Configurar backend.hcl: staging usa oficina/staging/backend.tfstate;
   producao usa oficina/producao/backend.tfstate. Nunca reutilizar o mesmo estado.
4. Inicializar o backend S3, gerar e revisar o plan autenticado. Aplicar somente
   na etapa de provisionamento, com identidade autorizada.
5. Instalar o controlador compartilhado conforme [runbook](../docs/controller.md).
6. Criar o namespace correspondente com RBAC/NetworkPolicies e preparar a API.

Depois do apply deste root, exportar os documentos em um terminal PowerShell
conectado a conta/cluster corretos. Os arquivos gerados ficam ignorados no Git:

```powershell
$manifest = terraform -chdir=backend output -raw kubernetes_manifest
if ($LASTEXITCODE -ne 0) { throw 'Falha ao obter manifesto do backend.' }
[IO.File]::WriteAllText((Join-Path (Get-Location) 'backend/api-backend.generated.yaml'), ($manifest -join "`n"), [Text.UTF8Encoding]::new($false))
kubectl config current-context
kubectl get namespace oficina-staging
kubectl apply --dry-run=server -f backend/api-backend.generated.yaml
# Depois de conferir contexto, namespace e resultado:
kubectl apply -f backend/api-backend.generated.yaml
```

Para producao, usar o state/tfvars correspondentes e conferir oficina-producao.
O namespace nao e criado implicitamente. Se usar a injecao de readiness gates do
LBC, criar Service/TGB e label de injecao no namespace ANTES dos pods.
O deploy da API deve usar app=oficina-api e escutar em 8080.

Obter customer_backend e transferir o objeto para o input homonimo do gateway/
do MESMO ambiente (nao transferir tfstate). Conferir output backend.environment.
Habilitar a integracao somente apos targets saudaveis, VPC Link AVAILABLE e
auth/discovery/JWKS verificados, conforme o [runbook Gateway](../gateway/README.md).

## Verificacao real

```powershell
kubectl get targetgroupbinding -n oficina-staging
kubectl get endpointslices -n oficina-staging -l kubernetes.io/service-name=oficina-api
kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=100
$backend = terraform -chdir=backend output -json backend | ConvertFrom-Json
aws elbv2 describe-target-health --target-group-arn $backend.target_group_arn --region $backend.aws_region
$customerBackend = terraform -chdir=backend output -json customer_backend | ConvertFrom-Json
aws apigatewayv2 get-vpc-link --vpc-link-id $customerBackend.vpc_link_id --region $backend.aws_region
```

Conferir somente IPs dos pods do ambiente e health healthy. Repetir smoke tests
externos: cliente autentica, cria/aprova sua OS; outro cliente recebe 404.
Erros 502/503 podem indicar targets ausentes/unhealthy; 403 exige examinar JWT/role.
Validacao local nao comprova quotas, permissao IAM real, conectividade ou readiness.
Os logs de acesso do Gateway ja existem; access logs do ALB em S3 nao sao configurados aqui.

## Remocao

Primeiro desativar integracoes do Gateway. Remover TGB enquanto o controlador ainda
esta ativo, aguardando desregistro/finalizers; depois remover Service/workloads.
Para remover o ALB, aplicar allow_destroy=true e revisar o plano de destruicao
do backend. Nao remover controlador/fundacao antes das dependencias. Um simples
merge ou exclusao de state nao cria nem apaga recursos.

Referencias: [integracao privada HTTP API](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-private.html),
[TargetGroupBinding](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/targetgroupbinding/targetgroupbinding/).
