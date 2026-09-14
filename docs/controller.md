# Controlador de targets do EKS

Instalar UMA release compartilhada de AWS Load Balancer Controller em kube-system.
O Terraform infra/ prepara IRSA e exporta load_balancer_controller_values; nao
instala Helm nem acessa o endpoint Kubernetes durante seus testes.

Versao de referencia fixada: chart 3.5.0 / controller v3.5.0 do repositorio EKS.
Os values fixam regiao e VPC para dispensar descoberta via IMDS (workers usam
hop limit 1). O service account recebe sua propria role IRSA, sem credenciais estaticas.

## Permissoes e limites

A trust policy aceita somente kube-system/aws-load-balancer-controller, audience
sts.amazonaws.com, no provider OIDC deste cluster. A policy permite Describe de
VPCs, SGs, instancias e targets; RegisterTargets/DeregisterTargets ficam restritos
aos ARNs dos target groups de staging/producao deste projeto, conta e regiao.

Nao ha CreateLoadBalancer, CreateTargetGroup, ModifyTargetGroup ou edicao de SG.
Este modo usa TGB com targetType=ip e vpcID explicitos e sem spec.networking.
A configuracao e os SGs sao gerenciados pelo Terraform; o controlador gerencia
a associacao dos pods. A policy de referencia completa de Ingress nao deve ser
anexada a essa role. Se futuramente adotar outro modo, revisar ownership e IAM.

Os values desativam criacao automatica de backend SG, mutacao de Services
LoadBalancer, controller de Services e suporte Gateway API ALB/NLB.
Nao criar Ingress: esta instalacao se destina apenas a TargetGroupBinding.

O controlador e compartilhado, portanto sua role pode registrar targets nos dois
ambientes. Limitar criacao/edicao de TGB a administradores/pipeline do backend.
Nao conceder essa permissao aos service accounts da API nem usar o role do
controlador nos pods da aplicacao. RBAC/NetworkPolicies de workloads serao
entregues com o deploy da API; namespaces nao isolam a rede por si so.

## Instalacao futura, apos EKS e acesso administrativo

Requer Helm, kubectl e conectividade com o endpoint privado. O SG atual do EKS
e compartilhado por control plane/nodes e sua regra self permite o webhook 9443.
Se os SGs forem separados, preservar TCP 9443 do control plane ao controlador.

Na raiz do repositorio:

```powershell
$values = terraform -chdir=infra output -raw load_balancer_controller_values
if ($LASTEXITCODE -ne 0) { throw 'Falha ao obter values do controlador.' }
[IO.File]::WriteAllText((Join-Path (Get-Location) 'infra/controller.generated.yaml'), ($values -join "`n"), [Text.UTF8Encoding]::new($false))
kubectl config current-context
kubectl get nodes
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm show chart eks/aws-load-balancer-controller --version 3.5.0
helm template aws-load-balancer-controller eks/aws-load-balancer-controller --version 3.5.0 --namespace kube-system --values infra/controller.generated.yaml
# Apos conferir cluster e manifests:
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller --version 3.5.0 --namespace kube-system --values infra/controller.generated.yaml --wait --timeout 5m
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system
kubectl get crd targetgroupbindings.elbv2.k8s.aws
```

Helm instala CRDs na primeira instalacao. Em upgrade, atualizar previamente os
CRDs da MESMA versao do chart e conferir compatibilidade; helm upgrade nao faz
essa atualizacao automaticamente. Nao usar URLs de main para atualizar producao.

Depois instalar o Service/TGB exportado por backend/, no namespace certo, e o
Deployment da API. Confira [validacao dos targets e desmontagem](../backend/README.md).
Nao ha instalacao remota nesta entrega. Testes Terraform verificam IAM/values,
mas nao substituem reconciliacao real no EKS.

Fontes fixadas:
[instalacao e modo TGB](https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/v3.5.0/docs/deploy/installation.md),
[values oficiais](https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/v3.5.0/helm/aws-load-balancer-controller/values.yaml),
[reconciliacao de TGB](https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/v3.5.0/pkg/targetgroupbinding/resource_manager.go).
