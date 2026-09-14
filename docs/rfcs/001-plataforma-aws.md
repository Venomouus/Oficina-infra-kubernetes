# RFC 001 - Plataforma AWS para demonstracao do Tech Challenge

Status: aceita para implementacao incremental. Validacao em nuvem pendente.

## Problema

Demonstrar Kubernetes escalavel, banco gerenciado, autenticacao serverless, Gateway,
CI/CD e observabilidade sem manter infraestrutura cobrada durante todo o desenvolvimento.

## Proposta

Desenvolver com Docker/kind e testes locais. Preparar Terraform e pipelines antes
de provisionar. Usar EKS, RDS PostgreSQL, Lambda e API Gateway na janela de demonstracao,
com dados de teste e controle do periodo de uso. PostgreSQL mantem compatibilidade
com a persistencia EF Core e a consulta de autenticacao ja implementadas.

Terraform entrega recursos e contratos de saida entre os quatro repositorios.
Este PR entrega a fundacao VPC/EKS; RDS, funcoes, Gateway e CD avancam em alteracoes
separadas, com dependencias explicitas e evidencias em cada etapa.

## Alternativas

- Apenas kind local: adequado ao desenvolvimento, mas nao demonstra deploy na nuvem
  e banco gerenciado exigidos pelo desafio.
- Kubernetes autogerenciado em EC2: exige operacao do control plane e recuperacao
  de falhas pelo projeto; foi preterido para priorizar a demonstracao de integracoes.
- Dois EKS independentes: separacao mais forte, mas maior quantidade de recursos
  durante o laboratorio. Reavaliar para uso corporativo.

## Custos e restricoes

A escolha AWS nao pressupoe gratuidade. O custo envolve cluster EKS, workers, discos,
NAT/IPv4, banco, trafego e monitoramento. Confirmar acesso aos servicos no plano da
conta, creditos restantes e estimativa para a duracao real antes do primeiro apply.
Nao publicar uma estimativa como valor garantido sem consultar a conta e a regiao.

Referencias: [EKS pricing](https://aws.amazon.com/eks/pricing/),
[VPC pricing](https://aws.amazon.com/vpc/pricing/) e
[versoes suportadas EKS](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html).

## Criterios de aceite da entrega completa

Gateway roteando, Lambda emitindo JWT apos consulta ao RDS, API no EKS autorizando
clientes e administradores, HPA demonstrado, notificacoes entregues, pipelines de
ambos os ambientes, logs/traces correlacionados, dashboards/alertas e documentacao.
A validacao local do Terraform deste PR comprova apenas consistencia e invariantes
da configuracao, nao o aceite completo da arquitetura.
