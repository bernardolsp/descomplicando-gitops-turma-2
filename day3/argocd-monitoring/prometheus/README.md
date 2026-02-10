# Prometheus + Grafana

Configuração do kube-prometheus-stack para monitorar Argo CD.

## Instalação

Já incluído no `install.sh` do diretório pai.

Manual:
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f values.yaml
kubectl apply -f argocd-dashboard.yaml
```

## Acesso

```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

Login: `admin` / `admin`

## Dashboard

O arquivo `argocd-dashboard.yaml` cria um ConfigMap que é automaticamente importado pelo Grafana.

Painéis incluídos:
- Total de aplicações
- Queue depth (indicador de backpressure)
- Apps syncing / out of sync / healthy / degraded
- Taxa de reconciliação
- Latência de reconciliação (p50, p95)
- Operações de sync por fase
- Requisições Git
- Requisições K8s API
