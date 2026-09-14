# Plataforma compartilhada AWS

Este root declara recursos AWS reais. Nesta entrega foi validado somente com
fmt, validate e testes mockados. Nenhum apply ou plan autenticado foi executado.

## Arquivos

| Arquivo | Responsabilidade |
|---|---|
| versions.tf | Terraform, provider e backend S3 parcial |
| main.tf | Provider, conta autorizada, nomes e tags |
| variables.tf / eks-variables.tf | Contratos e validacoes de entrada |
| network.tf | VPC, subnets, rotas, NAT, S3 e SGs de origem das Lambdas |
| eks.tf | IAM, cluster, acesso, workers, addons e logs |
| outputs.tf | Contrato de saida para os outros repositorios |
| tests/platform.tftest.hcl | Oito cenarios com AWS mockado |
| .terraform.lock.hcl | Versao e checksums do provider |

## Validacao de desenvolvimento

```powershell
terraform -chdir=infra fmt -check -recursive
terraform -chdir=infra init -backend=false -input=false -lockfile=readonly
terraform -chdir=infra validate -no-color
terraform -chdir=infra test -no-color
```

Nao precisa copiar tfvars nem configurar AWS para esses comandos.
Os testes verificam redes isoladas, saida por NAT, endpoint privado/restrito,
administradores explicitos, configuracao dos workers e rejeicao de entradas perigosas.
Mesmo os runs de teste com `command = apply` utilizam exclusivamente o provider
mockado; eles nao chamam a AWS.

## Parametros para o futuro plan

Copiar terraform.tfvars.example para terraform.tfvars e substituir a conta/role
ilustrativas somente quando for preparar o deploy autenticado.

- aws_account_id: conta que o provider pode usar.
- cluster_admin_principal_arns: identidades IAM reais autorizadas no Kubernetes.
  O Terraform nao cria essas identidades. O administrador implicito de criacao fica desabilitado.
- eks_public_access_cidrs: vazio mantem endpoint privado. Para acesso local,
  indicar seu IP publico/32; a regra rejeita redes mais amplas que /24.
- node_scaling: 2 <= min <= desired <= max <= 6. Capacidade inicial 2; maximo 3.
- nat_mode: single no laboratorio, per_az para saida independente por zona.
- kubernetes_version: 1.35 por padrao; confirmar suporte na regiao/conta.
- addon_versions: null consulta defaults compativeis. Apos o primeiro plan,
  fixar as quatro versoes validadas antes da promocao, evitando atualizacoes implicitas.

EKS em suporte STANDARD evita optar por suporte estendido. Ao encerrar o suporte,
a AWS pode atualizar a versao; planejar upgrades e revisar o Terraform antes disso.
Consultar [ciclo de versoes EKS](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html).

## Estado remoto e identidade de CI

O bucket de estado deve existir antes de inicializar este backend. Seu bootstrap,
versionamento, criptografia, bloqueio de acesso publico e politicas OIDC de GitHub
ainda serao implementados em uma alteracao propria.

Exemplo de chave unica para a plataforma: oficina/shared/platform.tfstate.
Preparar backend.hcl a partir de backend.hcl.example, sem credenciais no arquivo.
O locking usa arquivo S3 (`use_lockfile=true`), exigindo Terraform >= 1.10.

Depois do bootstrap e da configuracao de acesso, a sequencia futura sera:

```powershell
terraform -chdir=infra init -reconfigure -backend-config=backend.hcl
terraform -chdir=infra plan -var-file=terraform.tfvars -out=platform.tfplan
# Revisar o plano e a estimativa antes de executar:
terraform -chdir=infra apply platform.tfplan
```

Esses comandos de deploy nao foram executados nesta entrega. DEPLOY_ENABLED controla
apenas jobs que consultem a variavel; nao bloqueia um apply manual.
O plano pode conter dados de infraestrutura e nao deve ser publicado junto ao codigo.

O endpoint EKS privado requer acesso de rede para kubectl/Helm. A etapa de CD devera
providenciar runner com conectividade privada ou egress fixo autorizado. Nao abrir
0.0.0.0/0 para viabilizar runners GitHub com IPs variaveis.
O OIDC deste root e **do EKS para pods (IRSA)**; nao e o futuro OIDC GitHub Actions.

## Verificacoes depois do provisionamento

Com identidade autorizada e acesso ao endpoint Kubernetes:

```powershell
aws eks update-kubeconfig --region us-east-1 --name oficina-lab-eks
kubectl get nodes -o wide
kubectl get pods -n kube-system
kubectl top nodes
terraform -chdir=infra output -json platform
```

Confirmar workers nas subnets privadas, distribuicao real entre zonas, CNI/DNS,
metrics-server, acesso e logs do control plane. A distribuicao de replicas da API
ainda depende dos manifests do outro repositorio.

Nao existe aplicacao instalada nem URL de negocio neste root. O HPA da API fica
na Oficina-Mecanica. Cluster Autoscaler/Karpenter ainda precisa ser instalado
para ajustar nos automaticamente; min/max do node group sozinho nao faz isso.
Ao adotar um autoscaler, documentar seu ownership de desired_size e ajustar
o lifecycle correspondente para o Terraform nao desfazer a escala.

## Remocao planejada

Preservar evidencias e backups. Remover primeiro Gateway/VPC Link e balanceadores,
workloads, Lambdas com interfaces na VPC e RDS, nos seus respectivos estados.
A fundacao e removida por ultimo, depois de revisar um plano de destruicao:

```powershell
terraform -chdir=infra plan -destroy -var-file=terraform.tfvars -out=destroy.tfplan
# Aplicar apenas depois de revisar dependencias e backups:
terraform -chdir=infra apply destroy.tfplan
```

O bucket de estado tem ciclo de vida separado e nao e removido por esse root.
Snapshots finais de RDS e logs preservados podem continuar existindo/cobrando;
verificar a conta apos encerrar o laboratorio.
