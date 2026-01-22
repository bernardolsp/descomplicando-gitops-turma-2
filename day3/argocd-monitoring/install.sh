#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Instalando Argo CD + Prometheus ==="
echo ""

# Add Helm repos
echo "[1/4] Adicionando repositórios Helm..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

# Create namespaces
echo "[2/4] Criando namespaces..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Install Argo CD
echo "[3/4] Instalando Argo CD..."
helm upgrade --install argocd argo/argo-cd \
  -n argocd \
  -f "$SCRIPT_DIR/values.yaml" \
  --wait

# Install Prometheus
echo "[4/4] Instalando Prometheus + Grafana..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f "$SCRIPT_DIR/prometheus/values.yaml" \
  --wait

# Apply Grafana dashboard
echo ""
echo "Aplicando dashboard do Argo CD no Grafana..."
kubectl apply -f "$SCRIPT_DIR/prometheus/argocd-dashboard.yaml"

echo ""
echo "=== Instalação Completa! ==="
echo ""
echo "Argo CD:"
echo "  kubectl port-forward -n argocd svc/argocd-server 8080:80"
echo "  URL: http://localhost:8080"
echo "  Senha admin: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "Grafana:"
echo "  kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
echo "  URL: http://localhost:3000"
echo "  Login: admin / admin"
echo ""
echo "Próximos passos:"
echo "  1. Aplicar stress test: kubectl apply -f $SCRIPT_DIR/stressing-argo/applicationset.yaml"
echo "  2. Disparar syncs: $SCRIPT_DIR/stressing-argo/trigger-sync.sh"
echo "  3. Observar métricas no Grafana!"
