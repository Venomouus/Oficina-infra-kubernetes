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
acesso publico, backups, credenciais e bancos logicos por ambiente. Ingress 5432
deve referenciar SG, sem liberar CIDR publico. Criar tambem egress 5432 dos SGs
Lambda ao SG RDS, usando aws_vpc_security_group_egress_rule naquele repo.
A plataforma nao gerencia essas regras de banco em paralelo.

## Aplicacao e serverless

Os manifests da API recebem endereco/credenciais do RDS, issuer/audience do cliente
e namespace correspondente. A API verifica role e propriedade da OS mesmo quando
o Gateway valida o JWT. A Lambda recebe private_subnet_ids e o SG do seu ambiente,
consulta RDS e usa chave privada guardada em gerenciador de segredos.

## Gateway (proxima camada neste repositorio)

Planejado API Gateway HTTP API, VPC Link e ALB interno, com destino por ambiente.
O ALB sera gerenciado por Terraform da plataforma e os targets serao registrados
pelo AWS Load Balancer Controller via TargetGroupBinding, apos instalar o controller.
Nao criar o mesmo ALB tambem via Ingress/Service do Kubernetes.

Mapa inicial de rotas a implementar e testar:

| Rota | Destino | Controle |
|---|---|---|
| POST /auth/cpf | Lambda auth v2 | Publica, com limitacao de tentativas |
| GET /.well-known/jwks.json e openid-configuration | Lambda auth | Publica, apenas metadados/chaves publicas |
| /api/minhas-ordens-servico e subrotas | ALB -> API | Autorizador JWT RS256 + scope oficina:cliente; API verifica propriedade |
| /api/auth/login | ALB -> API | Login administrativo, sem exigir JWT de cliente |
| Demais rotas /api | ALB -> API | API aplica politicas de cliente/admin e segredo do webhook |

O autorizador JWT nativo HTTP API nao deve ser imposto globalmente: o login
administrativo atual emite HS256, enquanto o JWT de cliente e RS256. As rotas
administrativas continuam exigindo validacao na API. Consulte o
[autorizador JWT HTTP API](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-jwt-authorizer.html).
Nao deixar uma rota proxy
sem as politicas da API nem publicar diretamente o ALB na internet.

Para evitar dependencia circular entre issuer e Lambda: criar o Gateway e sua URL
antes das integracoes, configurar o issuer na Lambda/API, depois conectar ARN da
funcao e listener do ALB. A separacao dos roots dessa camada sera implementada
com o Gateway, sem terraform -target como fluxo normal.

## Sequencia de deploy a implementar

1. Bootstrap: bucket de estado, GitHub OIDC e roles de CI/CD.
2. Fundacao compartilhada: este root VPC/EKS.
3. Banco RDS e componentes Kubernetes (namespaces, RBAC, NetworkPolicy, controller e autoscaler).
4. Gateway/ALB por ambiente, inicialmente sem integracoes de Lambda.
5. Funcoes com issuer da URL publica e conexao RDS; deploy da API com migrations.
6. Integracoes/rotas Gateway e targets do ALB; smoke tests externos.
7. Instrumentacao, dashboards/alertas e evidencia dos dois ambientes.

Cada recurso tera um unico dono/estado. Ambos os ambientes precisam de CD automatico,
ainda nao implementado. A fundacao e compartilhada e sera aplicada pela master;
deploys especificos de develop/master usam seus proprios estados/locks. O ciclo de
alteracoes compartilhadas afeta os dois ambientes e deve constar da demonstracao.
