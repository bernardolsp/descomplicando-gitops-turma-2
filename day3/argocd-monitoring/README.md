# Argo CD Monitoring & Stress Testing

Este diretório contém tudo necessário para:
- Instalar Argo CD com métricas habilitadas
- Instalar Prometheus + Grafana para monitoramento
- Gerar centenas de aplicações para stress test
- Monitorar o comportamento do Argo CD sob carga

## Estrutura

```
argocd-monitoring/
├── install.sh                    # Script único para instalar tudo
├── values.yaml                   # Valores do Argo CD (OIDC + métricas)
├── prometheus/
│   ├── values.yaml               # Valores do kube-prometheus-stack
│   ├── argocd-dashboard.yaml     # Dashboard Grafana para Argo CD
│   └── README.md
└── stressing-argo/
    ├── README.md
    ├── base-chart/               # Helm chart simples para stress test
    ├── applicationset.yaml       # Gera 200 apps automaticamente
    ├── trigger-sync.sh           # Dispara syncs em massa
    └── cleanup.sh                # Remove tudo
```

## Quick Start

```bash
# 1. Instalar Argo CD + Prometheus
./install.sh

# 2. Acessar Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Login: admin / admin

# 3. Acessar Argo CD
kubectl port-forward -n argocd svc/argocd-server 8080:80

# 4. Aplicar stress test (200 apps)
kubectl apply -f stressing-argo/applicationset.yaml

# 5. Disparar syncs em massa
./stressing-argo/trigger-sync.sh

# 6. Observar métricas no Grafana!

# 7. Cleanup
./stressing-argo/cleanup.sh
```

## Métricas Importantes

| Métrica | O que mostra |
|---------|--------------|
| `workqueue_depth` | Profundidade da fila (backpressure!) |
| `argocd_app_reconcile_bucket` | Latência de reconciliação |
| `argocd_app_sync_total` | Operações de sync |
| `argocd_git_request_total` | Requisições ao Git |

## PromQL Úteis

```promql
# Total de aplicações
count(argocd_app_info)

# Queue depth (mostra saturação)
workqueue_depth{name=~"app_operation.*|app_reconciliation.*"}

# Taxa de reconciliação
sum(rate(argocd_app_reconcile_count[5m]))

# P95 latência de reconciliação
histogram_quantile(0.95, sum(rate(argocd_app_reconcile_bucket[5m])) by (le))
```
