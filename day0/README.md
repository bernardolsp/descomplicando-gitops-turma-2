# Day 0 - Contexto e Setup

## 📋 Objetivos

- Entender os princípios de GitOps
- Compreender a arquitetura do ArgoCD
- Configurar ambiente de desenvolvimento
- Preparar clusters para os próximos dias

---

## 🎓 Conceitos de GitOps

### O que é GitOps?

GitOps é uma metodologia de entrega contínua que utiliza Git como fonte única de verdade para infraestrutura e aplicações.

**Princípios fundamentais:**
1. **Declarativo**: Todo o estado desejado do sistema é descrito declarativamente
2. **Versionado**: O estado desejado é armazenado em Git
3. **Automatizado**: Mudanças aprovadas são aplicadas automaticamente
4. **Reconciliação**: Agentes garantem que o estado real corresponde ao estado desejado

### Por que GitOps?

**Benefícios:**
- ✅ **Auditoria completa**: Histórico de todas as mudanças no Git
- ✅ **Rollback fácil**: Reverter para qualquer commit anterior
- ✅ **Disaster Recovery**: Cluster pode ser recriado a partir do Git
- ✅ **Colaboração**: Pull Requests para revisar mudanças
- ✅ **Segurança**: Git como ponto único de autenticação
- ✅ **Produtividade**: Desenvolvedores usam ferramentas familiares

---

## 🏗️ Arquitetura do ArgoCD

```
┌─────────────────────────────────────────────────────┐
│                    Git Repository                    │
│  (Source of Truth - Kubernetes Manifests/Helm)      │
└──────────────────┬──────────────────────────────────┘
                   │
                   │ 1. Fetch manifests
                   │
┌──────────────────▼──────────────────────────────────┐
│              ArgoCD Components                       │
│  ┌────────────────────────────────────────────┐    │
│  │  ArgoCD Server (API + UI)                  │    │
│  └────────────────────────────────────────────┘    │
│  ┌────────────────────────────────────────────┐    │
│  │  Application Controller                     │    │
│  │  - Monitors Git repositories                │    │
│  │  - Compares desired vs actual state         │    │
│  │  - Reconciles differences                   │    │
│  └────────────────────────────────────────────┘    │
│  ┌────────────────────────────────────────────┐    │
│  │  Repo Server                                │    │
│  │  - Generates Kubernetes manifests           │    │
│  │  - Supports Helm, Kustomize, Jsonnet        │    │
│  └────────────────────────────────────────────┘    │
│  ┌────────────────────────────────────────────┐    │
│  │  Dex (SSO/OIDC)                             │    │
│  └────────────────────────────────────────────┘    │
└──────────────────┬──────────────────────────────────┘
                   │
                   │ 2. Apply manifests
                   │
┌──────────────────▼──────────────────────────────────┐
│            Kubernetes Cluster                        │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐            │
│  │   Pod    │ │ Service  │ │ Ingress  │            │
│  └──────────┘ └──────────┘ └──────────┘            │
└─────────────────────────────────────────────────────┘
                   │
                   │ 3. Report status
                   │
┌──────────────────▼──────────────────────────────────┐
│          Observability & Notifications               │
│  - Prometheus Metrics                                │
│  - Slack/Discord Notifications                       │
│  - Grafana Dashboards                                │
└─────────────────────────────────────────────────────┘
```

### Componentes Principais

1. **API Server**
   - Interface REST/gRPC
   - Autenticação e autorização
   - UI Web

2. **Application Controller**
   - Monitora Git repositories
   - Detecta drift (diferenças entre Git e cluster)
   - Executa sincronizações

3. **Repo Server**
   - Renderiza manifests (Helm, Kustomize)
   - Cache de repositórios
   - Geração de diffs

4. **ApplicationSet Controller**
   - Gerenciamento multi-cluster
   - Template de Applications
   - Geradores (Git, Cluster, Matrix)

---

## 🛠️ Setup do Ambiente

### Pré-requisitos

Execute o script de instalação:

```bash
cd ../setup
./install-prerequisites.sh
```

Isso instalará:
- Docker Desktop
- kubectl
- Helm 3
- KinD (Day 1)
- eksctl e AWS CLI (Days 2-5)
- ArgoCD CLI
- jq e yq

### Validar Instalação

```bash
cd ../scripts
./validate-environment.sh
```

---

## 🔧 Ambientes por Dia

### Day 1 - KinD (Kubernetes in Docker)

**Por que KinD?**
- ✅ Rápido para criar/destruir
- ✅ Leve (roda localmente)
- ✅ Perfeito para aprendizado
- ✅ Suporta multi-node
- ✅ Ingress controller fácil

**Limitações:**
- ❌ Não é production-ready
- ❌ Não tem HA real
- ❌ Não integra com cloud providers

**Criar cluster:**
```bash
cd ../setup
./create-kind-cluster.sh
```

**Instalar ArgoCD:**
```bash
./install-argocd-kind.sh
```

---

### Days 2-5 - Amazon EKS

**Por que EKS?**
- ✅ Production-ready
- ✅ HA nativo (3 AZs)
- ✅ Integração com AWS (IAM, Secrets Manager, Load Balancers)
- ✅ Auto-scaling
- ✅ Gerenciado (control plane)

**Características:**
- 3 Availability Zones
- 2 Node Groups (system + application)
- VPC dedicada com NAT Gateways HA
- IRSA (IAM Roles for Service Accounts)
- AWS Load Balancer Controller
- Metrics Server

**Criar cluster:**
```bash
# Configurar AWS
aws configure

# Criar cluster (15-20 minutos)
cd ../setup
./create-eks-cluster.sh
```

**Instalar ArgoCD HA:**
```bash
./install-argocd-eks.sh
```

**⚠️ IMPORTANTE - Custos AWS:**

O cluster EKS custa aproximadamente **$770/mês** se deixado rodando 24/7.

**Para reduzir custos:**
```bash
# Deletar quando não estiver usando
eksctl delete cluster --name argocd-training --region us-east-1

# Recriar quando necessário
./create-eks-cluster.sh
```

**Configurar Budget Alerts (recomendado):**
```bash
aws budgets create-budget \
    --account-id $(aws sts get-caller-identity --query Account --output text) \
    --budget file://budget-config.json
```

---

## 📊 Comparação dos Ambientes

| Característica | KinD (Day 1) | EKS (Days 2-5) |
|---------------|--------------|----------------|
| **Setup** | 5 minutos | 15-20 minutos |
| **Custo** | Grátis | ~$770/mês |
| **HA** | Simulado | Real (3 AZs) |
| **Produção** | ❌ | ✅ |
| **Cloud Integration** | ❌ | ✅ AWS |
| **Multi-cluster** | Manual | Nativo |
| **Performance** | Limitado | Escalável |
| **Persistência** | Efêmera | Persistente |

---

## 🎯 Checklist Day 0

- [ ] Todas as ferramentas instaladas (`./scripts/validate-environment.sh`)
- [ ] Docker rodando
- [ ] kubectl configurado
- [ ] AWS CLI configurado (para Days 2-5)
- [ ] Cluster KinD criado (para Day 1)
- [ ] ArgoCD instalado no KinD
- [ ] Acesso à UI do ArgoCD

---

## 📚 Material de Leitura

**Antes de começar Day 1, leia:**

1. [GitOps Principles](https://opengitops.dev/)
2. [ArgoCD Core Concepts](https://argo-cd.readthedocs.io/en/stable/core_concepts/)
3. [Kubernetes Objects](https://kubernetes.io/docs/concepts/overview/working-with-objects/)

**Vídeos recomendados:**
- [Introduction to GitOps](https://www.youtube.com/watch?v=f5EpcWp0THw)
- [ArgoCD in 15 minutes](https://www.youtube.com/watch?v=MeU5_k9ssrs)

---

## 🆘 Troubleshooting

### Docker não inicia
```bash
# macOS
open -a Docker

# Linux
sudo systemctl start docker
```

### KinD cluster não cria
```bash
# Verificar Docker
docker ps

# Limpar clusters antigos
kind delete cluster --name argocd-day1

# Recriar
./setup/create-kind-cluster.sh
```

### AWS CLI não configurado
```bash
# Configurar interativamente
aws configure

# Ou via variáveis de ambiente
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="us-east-1"
```

---

## ➡️ Próximos Passos

1. ✅ Validar que todo o ambiente está OK
2. ✅ Acessar ArgoCD UI
3. ✅ Familiarizar-se com a interface
4. ➡️ Prosseguir para [Day 1 - Applications](../day1/)

---

**Duração estimada**: 1-2 horas

**Dificuldade**: ⭐ (Básico)
