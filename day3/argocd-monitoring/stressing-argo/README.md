# Stress Testing Argo CD

Ferramentas para gerar centenas de aplicações e estressar o Argo CD.

## Como Funciona

1. **ApplicationSet** gera 200 apps (10 batches x 20 variações)
2. **Helm chart** simples deploya nginx com ConfigMap
3. **trigger-sync.sh** dispara syncs em massa
4. **Prometheus** coleta métricas de queue, latência, etc.

## Uso

```bash
# Aplicar ApplicationSet (cria 200 apps)
kubectl apply -f applicationset.yaml

# Observar criação
kubectl get applications -n argocd -l app.kubernetes.io/part-of=stress-test --watch

# Disparar syncs em massa
./trigger-sync.sh

# Cleanup
./cleanup.sh
```

## Opções do trigger-sync.sh

```bash
./trigger-sync.sh --batch-size 50 --delay 2
./trigger-sync.sh --hard-refresh
./trigger-sync.sh --help
```

## Métricas para Observar

Durante o stress test, observe no Grafana:
- `workqueue_depth` - Quando > 0, há backpressure
- `argocd_app_reconcile_bucket` - Latência aumenta sob carga
- `argocd_git_request_total` - Repo server pode virar gargalo
