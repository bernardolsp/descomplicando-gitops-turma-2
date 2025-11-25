Treinamento ArgoCD - Dia 1: Application CRD

Neste módulo, focaremos no Application Custom Resource Definition (CRD), o objeto primário do ArgoCD responsável por definir o deployment de uma aplicação Kubernetes de forma declarativa.

O Application CRD gerencia a relação entre o Desired State (Git) e o Live State (Cluster).

# 1. Visão Geral do Recurso

Ao aplicar um manifesto do tipo Application no cluster de gerenciamento (onde o ArgoCD roda), o controller inicia o loop de reconciliação:

- **Source**: Onde estão os manifestos (Git, Helm, Kustomize).

- **Destination**: Onde a carga de trabalho será executada (Cluster API URL + Namespace).

O controller compara continuamente o estado atual com o estado desejado.

- **Synced**: O cluster reflete exatamente o Git.

- **OutOfSync**: Há divergência (drift) ou novos commits pendentes.

# 2. Spec do Application

Abaixo, um manifesto típico com as configurações essenciais para o setup inicial.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook-app
  namespace: argocd # Namespace do control plane do ArgoCD
spec:
  project: default
  
  # 1. SOURCE (Desired State)
  source:
    repoURL: [https://github.com/argoproj/argocd-example-apps.git](https://github.com/argoproj/argocd-example-apps.git)
    targetRevision: HEAD  # Branch, Tag, ou Commit SHA específico
    path: guestbook       # Caminho relativo dentro do repo
  
  # 2. DESTINATION (Target)
  destination:
    server: [https://kubernetes.default.svc](https://kubernetes.default.svc) # URL da API do cluster destino
    namespace: guestbook-ui
  
  # 3. SYNC POLICY (Behavior)
  syncPolicy:
    automated: 
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

# 3. SyncPolicy e Estratégias de Reconciliação

A seção syncPolicy define a autonomia do controller sobre o cluster.

**Automated vs. Manual**

**Manual (Default)**: O ArgoCD detecta diffs, marca o app como OutOfSync, mas aguarda intervenção humana (via UI ou CLI) para aplicar as mudanças.

**Automated**: O controller aplica as mudanças automaticamente assim que detecta alterações no Git (polling default de 3 minutos ou via Webhook).

Parâmetros Críticos do Automated Sync:

- **A. Prune (prune: true)**

Controla a **Garbage Collection** de recursos.

- Behavior: Se um recurso é removido do Git, ele deve ser deletado do Cluster?

- Default (false): O ArgoCD ignora recursos deletados no Git para evitar remoções acidentais. O recurso fica órfão no cluster.

- Recomendado: true para garantir paridade total com o Git.

- **B. SelfHeal (selfHeal: true)**

Controla a correção automática de Configuration Drifts.

- Behavior: Se ocorrer uma alteração ad-hoc no cluster (ex: kubectl edit/patch), o ArgoCD deve reverter?

- Default (false): O ArgoCD marca como OutOfSync mas mantém a alteração manual.

- Recomendado: true. Isso força o estado do Git sobre o cluster imediatamente, revertendo alterações manuais não autorizadas.

# 4. Configurações Avançadas Relevantes

**Server-Side Apply**

Instrui o ArgoCD a utilizar o kubectl apply --server-side.

- Mecanismo: Transfere a lógica de cálculo de patch (diff) do client (ArgoCD) para o Kubernetes API Server.

- Uso: Essencial para aplicar CRDs que excedem o limite de tamanho de anotação do kubectl ou para resolver conflitos de fieldManager.

**Sync Options**

- CreateNamespace=true: Garante a criação do namespace definido em destination.namespace caso ele não exista. Evita falhas de sync no primeiro deploy.

- ApplyOutOfSyncOnly=true: Em aplicações com muitos recursos, aplica apenas os objetos que mudaram, reduzindo carga na API do K8s.

# 5. Fluxo de Execução

1. Commit: Alteração pushada para o repositório.

2. Refresh: ArgoCD detecta a mudança (Polling ou Webhook).

3. Reconciliation: Comparação hash/manifesto.

4. Action:

- Se automated: Aplica o manifesto.

- Se prune=true: Remove recursos deletados do Git.

- Se selfHeal=true: Sobrescreve drifts manuais.