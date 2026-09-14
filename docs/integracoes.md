# Contratos e ordem de integracao

## Output platform (contract_version = 1)

| Campo | Consumidor e uso |
|---|---|
| aws_region, vpc_id | Todos os repositorios AWS |
| cluster_name, cluster_arn | Deploy da API e componentes Kubernetes |
| private_subnet_ids | Lambdas em VPC, VPC Link e ALB interno |
| database_subnet_ids | DB subnet group do RDS |
| application_security_group_id | Origem autorizada para PostgreSQL, compartilhada pelos nodes/pods |
| lambda_security_group_ids.staging/producao | SG anexado as Lambdas de cada ambiente |
| oidc_provider_arn, oidc_issuer_url | IAM/IRSA dos workloads Kubernetes |
| environments | Branches e namespaces previstos |

Os IDs reais so existem depois do apply. Ler via output do estado compartilhado
e transmitir por mecanismo controlado (outputs de pipeline/SSM, a definir no CD).
Nao copiar tfstate nem conceder leitura irrestrita de estados com segredos entre repos.

## Banco

Oficina-infra-database recebe VPC, subnets isoladas e SGs de origem. Cria o RDS sem
acesso publico, backups e senha mestre gerenciada. Bancos logicos e roles por
ambiente ainda exigem bootstrap separado. Ingress 5432
deve referenciar SG, sem liberar CIDR publico. Criar tambem egress 5432 dos SGs
Lambda ao SG RDS, usando aws_vpc_security_group_egress_rule naquele repo.
A plataforma nao gerencia essas regras de banco em paralelo.

## Aplicacao e serverless

Os manifests da API recebem endereco/credenciais do RDS, issuer/audience do cliente
e namespace correspondente. A API verifica role e propriedade da OS mesmo quando
o Gateway valida o JWT. A Lambda recebe private_subnet_ids e o SG do seu ambiente,
consulta RDS e usa chave privada guardada em gerenciador de segredos.

## Gateway (root gateway/ neste repositorio)

Implementado HTTP API com um state por ambiente, integracao Lambda v2,
authorizer JWT e integracao privada opcional. O root backend/ implementa VPC Link e ALB
interno por ambiente e exporta customer_backend para o Gateway correspondente.
O ALB e o target group sao gerenciados pelo Terraform backend/; os targets serao registrados
pelo AWS Load Balancer Controller via TargetGroupBinding, apos instalar o controller.
Nao criar o mesmo ALB tambem via Ingress/Service do Kubernetes.

Mapa de rotas e estado da implementacao:

| Rota | Destino | Controle |
|---|---|---|
| POST /auth/cpf | Lambda auth v2 | Implementada, publica com throttling agregado |
| GET /.well-known/jwks.json e openid-configuration | Lambda auth | Publica, apenas metadados/chaves publicas |
| /api/minhas-ordens-servico e subrotas | ALB -> API | Autorizador JWT RS256 + scope oficina:cliente; API verifica propriedade |
| /api/auth/login | ALB -> API | Pendente; ainda nao publicada pelo Gateway |
| Demais rotas /api | ALB -> API | Pendentes; ainda nao publicadas pelo Gateway |

O autorizador JWT nativo HTTP API nao deve ser imposto globalmente: o login
administrativo atual emite HS256, enquanto o JWT de cliente e RS256. As rotas
administrativas continuam exigindo validacao na API. Consulte o
[autorizador JWT HTTP API](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-jwt-authorizer.html).
Nao deixar uma rota proxy
sem as politicas da API nem publicar diretamente o ALB na internet.

Para evitar dependencia circular entre issuer e Lambda: criar o Gateway e sua URL
antes das integracoes, configurar o issuer na Lambda/API, depois conectar ARN da
funcao e listener do ALB. O root gateway/ permite esse fluxo sem terraform -target.
O campo jwt_ready so deve ser ativado apos verificar os endpoints publicos de
discovery/JWKS. Backend de cliente exige jwt_ready e mantem JWT+scope em todas as
quatro rotas implementadas. Veja [runbook do Gateway](../gateway/README.md).

## Sequencia de deploy a implementar

1. Bootstrap: bucket de estado, GitHub OIDC e roles de CI/CD.
2. Fundacao compartilhada: root infra/ VPC/EKS e IAM do controlador.
3. Banco RDS e componentes Kubernetes (namespaces, RBAC, NetworkPolicy, controller e autoscaler).
4. Roots gateway/ e backend/ por ambiente, inicialmente sem integracoes de Lambda.
5. Funcoes com issuer da URL publica e conexao RDS; deploy da API com migrations.
6. Integracoes/rotas Gateway e targets do ALB; smoke tests externos.
7. Instrumentacao, dashboards/alertas e evidencia dos dois ambientes.

Cada recurso tera um unico dono/estado. Ambos os ambientes precisam de CD automatico,
ainda nao implementado. A fundacao e compartilhada e sera aplicada pela master;
deploys especificos de develop/master usam seus proprios estados/locks. O ciclo de
alteracoes compartilhadas afeta os dois ambientes e deve constar da demonstracao.

## Contratos do backend privado

- infra/ exporta load_balancer_controller_values para Helm, uma unica instalacao.
- backend/ recebe platform e environment; usa os namespaces definidos no contrato.
- backend/ exporta backend (v1: ambiente/regiao/cluster/namespace/ARNs) e
  customer_backend (vpc_id, vpc_link_id, listener_arn, server_name_to_verify).
- gateway/ recebe customer_backend do MESMO ambiente, apos targets saudaveis.
- kubernetes_manifest fornece Service ClusterIP e TGB de oficina-api; pods usam
  app=oficina-api, porta 8080 e health /health. Nao contem Deployment/segredos.
- IAM compartilhado permite registro apenas nos TGs do projeto nos dois ambientes.
  A administracao do backend controla TGB; RBAC deve impedir sua edicao por workloads.
- SGs de ALB/Link e ingress ALB->EKS pertencem somente a backend/. Sem networking
  no TGB; o controlador nao altera SGs nem provisiona balanceadores.

Estados: infra/ compartilhado; backend/ e gateway/ independentes por ambiente.
Nao usar o root backend/ como backend S3 de outro root: o nome designa o destino
privado da API. [Runbook](../backend/README.md) e [controlador](controller.md).
