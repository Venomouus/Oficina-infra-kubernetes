# API Gateway por ambiente

Este root cria um HTTP API com URL HTTPS gerenciada pela AWS e stage $default.
Cada ambiente usa um state separado. Nao executar este root no backend da VPC/EKS.

Implementado: API/stage, logs de acesso com retencao de sete dias, throttling,
integracao Lambda v2 por alias live, JWT authorizer e quatro rotas de cliente
via VPC Link/ALB interno quando os destinos estiverem configurados.

Nao implementa a criacao de VPC Link, ALB, listener, targets ou workloads.
Esses recursos ainda serao preparados na etapa de publicacao da API no EKS.
Nenhum recurso AWS foi provisionado durante o desenvolvimento.

## Validacao sem AWS

Na raiz do repositorio:

```powershell
terraform -chdir=gateway fmt -check -recursive
terraform -chdir=gateway init -backend=false -input=false -lockfile=readonly
terraform -chdir=gateway validate -no-color
terraform -chdir=gateway test -no-color
```

Sao 12 cenarios com mock_provider aws. Nao exigem credenciais nem endpoints reais.
A CI conserva o check validate-terraform e verifica os roots infra/ e gateway/.
Os oito testes da plataforma permanecem separados dos testes do Gateway.

## Estados e ownership

| Root | State previsto | Responsabilidade |
|---|---|---|
| infra/ | oficina/shared/platform.tfstate | VPC/EKS compartilhados |
| gateway/ com environment=staging | oficina/staging/gateway.tfstate | Gateway staging |
| gateway/ com environment=producao | oficina/producao/gateway.tfstate | Gateway producao |
| Oficina-serverless/infra | State serverless de cada ambiente | Lambda, alias, segredos e permissao de invocacao |

Copiar backend.hcl.example e terraform.tfvars.example somente na preparacao do
deploy. Substituir conta, bucket e identificadores. Para producao, alterar tanto
environment quanto a chave de backend. Nao reutilizar um state para os dois
ambientes nem importar os mesmos recursos em roots diferentes.

O futuro CD deve inicializar explicitamente o backend do ambiente em cada job.
DEPLOY_ENABLED continua false; este PR adiciona CI e codigo, sem executar apply.

## Bootstrap sem dependencias circulares

1. Preparar o bucket de state, identidade autorizada e a fundacao/rede.
2. No Gateway do ambiente, manter authentication=null, jwt_ready=false e
   customer_backend=null. O primeiro provisionamento cria URL/stage/logs, sem
   rotas de negocio. A URL responde 404 ate existirem rotas.
3. Ler o output gateway. No Oficina-serverless, configurar jwt_issuer com
   gateway.issuer e api_gateway_execution_arn com gateway.execution_arn.
4. Provisionar a Lambda e preencher os dois segredos conforme o runbook
   serverless. A permissao Lambda continua sendo gerenciada naquele repositorio.
5. Trazer os campos do output authentication para este root. Configurar a
   integracao e testar POST /auth/cpf e os dois endpoints well-known.
6. Somente depois de verificar discovery/JWKS publicos por HTTPS, ativar
   jwt_ready=true. Isso cria o authorizer com issuer/audience correspondentes.
7. Depois de publicar a API no EKS e preparar VPC Link/ALB, preencher
   customer_backend para habilitar as quatro rotas protegidas.

Esse fluxo usa os planos normais de cada root, sem terraform -target. O
jwt_ready permite separar a publicacao do emissor da criacao do authorizer,
que depende de um emissor acessivel. O teste mock nao verifica essa
acessibilidade nem as permissoes/quotas reais na AWS.

## Contrato authentication

Exemplo de estrutura; substituir pelos valores reais do output serverless:

```hcl
authentication = {
  contract_version = 1
  environment      = "staging"
  aws_region       = "us-east-1"
  alias_arn        = "arn:aws:lambda:us-east-1:123456789012:function:oficina-staging-autenticacao:live"
  issuer           = "https://ID-REAL.execute-api.us-east-1.amazonaws.com"
  audience         = "oficina-api"
}
```

O issuer precisa ser exatamente a URL do Gateway deste state, sem barra final.
A validacao rejeita outro projeto, conta, regiao, ambiente, alias ou audiencia.
O stage $default preserva os caminhos usados pelo handler Lambda v2. Dominio
customizado/base-path mapping nao esta configurado nesta entrega.

## Rotas e autorizacao

| Rota | Destino | Autorizacao no Gateway |
|---|---|---|
| POST /auth/cpf | Lambda live | Publica, throttling especifico |
| GET /.well-known/jwks.json | Lambda live | Publica |
| GET /.well-known/openid-configuration | Lambda live | Publica |
| GET /api/minhas-ordens-servico | API privada | JWT + scope oficina:cliente |
| POST /api/minhas-ordens-servico | API privada | JWT + scope oficina:cliente |
| GET /api/minhas-ordens-servico/{id} | API privada | JWT + scope oficina:cliente |
| POST /api/minhas-ordens-servico/{id}/aprovar | API privada | JWT + scope oficina:cliente |

O Gateway valida JWT RSA, issuer, audience, validade e scope. A API continua
validando perfil, cliente ativo e propriedade da OS. JWT criptograficamente
valido nao prova que a OS pertence ao solicitante.

Nao ha rota generica ANY /{proxy+}, login administrativo, Swagger, webhook ou
outras rotas administrativas publicadas por este root. O JWT administrativo
HS256 da API nao deve ser colocado no authorizer RSA do cliente. Publicacao
administrativa exige uma etapa explicita com suas proprias politicas.

Limites padrao: cinco requisicoes/segundo e burst dez nas rotas; auth usa
uma requisicao/segundo e burst dois. Sao limites agregados e best effort,
nao bloqueio por CPF/IP, protecao antifraude ou limite garantido de custos.
Nenhum CPF, token, corpo, query string, IP ou erro interno e incluido no formato
dos logs; ha somente IDs operacionais, routeKey, status, tamanho e latencia.
Metricas detalhadas e requisicoes do Gateway podem gerar custos.

## Backend privado opcional

```hcl
customer_backend = {
  vpc_id       = "vpc-ID-REAL"
  vpc_link_id  = "ID-REAL"
  listener_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/ALB/ID/ID"
  server_name_to_verify = "api.internal.example.com"
}
```

O VPC Link precisa estar AVAILABLE na mesma VPC do ALB e usar sub-redes/SGs
autorizados. Seu ID deve vir dos recursos controlados pela plataforma. O plano
consulta o listener e ALB: rejeita ALB publico, outra VPC e listener HTTPS sem
hostname de verificacao. Nao cria nem altera regras de rede implicitamente.

Para HTTPS, configurar certificado do listener e server_name_to_verify
correspondente. Para listener HTTP privado, omitir esse campo: nesse caso o
trecho Gateway→ALB usa HTTP, embora o endpoint externo continue HTTPS. Nao
declarar TLS ponta a ponta nesse modo. A escolha do listener sera feita junto
com o deploy da API.

O mapping overwrite:path=$request.path remove o prefixo de stage do encaminhamento.
As quatro rotas chamam a API pelo backend privado; a integracao usa ANY como
metodo de transporte, mas isso nao cria rotas publicas adicionais.

## Evidencias antes do video

Depois do provisionamento, testar separadamente staging e producao:

- Auth/discovery/JWKS acessiveis por HTTPS; issuer e audiencia corretos.
- Sem token, token expirado ou assinatura/audiencia/emissor incorretos: acesso negado.
- Token valido sem scope: acesso negado no Gateway.
- Token de cliente ativo: criacao/listagem/aprovacao da propria OS.
- OS de outro cliente: 404 na API; cliente inativo: acesso negado pela API.
- Rotas administrativas nao publicadas: 404 no Gateway.
- Limites de requisicoes e logs sem conteudo sensivel.
- ALB privado, SGs corretos e conectividade com o backend real.

Alem disso, concluir os itens restantes do enunciado: deploy/CD, notificacoes,
observabilidade e bootstrap do banco. A entrega deste root nao encerra o desafio.

Referencias oficiais:
[JWT authorizers](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-jwt-authorizer.html),
[integracoes privadas](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-develop-integrations-private.html),
[throttling](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-throttling.html).

## Remocao

Desabilitar/remover rotas e integracoes antes de remover VPC Link, listener e
Lambda. Remover a permissao de invocacao no state serverless. Apagar um state
nao remove seus recursos; revisar os planos de destruicao e recursos restantes.
