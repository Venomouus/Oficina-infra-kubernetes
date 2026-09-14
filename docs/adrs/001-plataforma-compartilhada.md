# ADR 001 - EKS compartilhado e estado unico da fundacao

Status: aceita para o laboratorio; operacao AWS ainda nao validada.

## Contexto

O desafio exige homologacao/producao com Kubernetes, Terraform e deploy automatico.
O projeto e individual, com desenvolvimento local e uso temporario de AWS para
demonstracao. Duplicar clusters e redes desde a preparacao aumenta o custo.

## Decisao

Compartilhar VPC e EKS no laboratorio, com um estado S3 da fundacao. Os ambientes
terao namespaces, configuracoes, bancos logicos, permissoes e roots de integracao
separados. A branch master sera a unica aplicadora da fundacao; develop valida
mudancas dessa camada. Os futuros roots por ambiente terao CD em ambas as branches.

Usar workers privados em duas zonas, no minimo dois nos, EKS Access Entries e
endpoint privado por padrao. Acesso publico de administracao exige CIDR restrito.
Usar IRSA para CNI, com role separada da role dos nos.

Usar um NAT por padrao para a janela curta do laboratorio. Oferecer per_az quando
a disponibilidade da saida for necessaria. HPA da API e autoscaler de nos sao
camadas diferentes: os limites do managed node group nao substituem esses controladores.

## Consequencias

Ha economia de quantidade de clusters/NATs, mas falhas e alteracoes compartilhadas
podem afetar os dois ambientes. Isso deve ser declarado no video e documentacao.
Namespaces sozinhos nao isolam rede, permissoes ou segredos. As politicas ainda
precisam ser implementadas antes de afirmar isolamento entre ambientes.

Aplicar o mesmo root em um estado staging e outro producao e proibido pelo desenho:
criaria ownership duplicado. O backend usara locking S3, e pipelines da fundacao
precisam de concurrency compartilhada sem cancelamento de um apply em andamento.

Esta decisao nao implementa os jobs de CD; eles permanecem como entrega obrigatoria.
Em operacao corporativa real, reavaliar contas/clusters separados, NAT por zona,
capacidade, politicas e protecao de dados conforme os requisitos de disponibilidade.
