#!/bin/bash
#
# install-argocd.sh
# Instala ArgoCD, Prometheus e Argo Rollouts para o Day 5
#

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Instalando ArgoCD + Prometheus +${NC}"
echo -e "${GREEN}  Argo Rollouts${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check prerequisites
log_step "Verificando pré-requisitos..."

if ! command -v kubectl &> /dev/null; then
    echo "Erro: kubectl não encontrado"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo "Erro: Helm não encontrado"
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    echo "Erro: kubectl não conectado a um cluster"
    exit 1
fi

log_success "Pré-requisitos OK"
echo ""

# Add Helm repos
log_step "Adicionando repositórios Helm..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update
log_success "Repositórios adicionados"
echo ""

# Create namespaces
log_step "Criando namespaces..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
log_success "Namespaces criados"
echo ""

# Install Prometheus FIRST (creates ServiceMonitor CRD)
log_step "[1/4] Instalando Prometheus + Grafana..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set grafana.enabled=true \
  --set grafana.adminPassword=admin \
  --set grafana.service.type=ClusterIP \
  --set alertmanager.enabled=false \
  --set kubeEtcd.enabled=false \
  --set kubeScheduler.enabled=false \
  --set kubeControllerManager.enabled=false \
  --set kubeProxy.enabled=false \
  --wait \
  --timeout 10m

log_success "Prometheus instalado"
echo ""

# Install ArgoCD
log_step "[2/4] Instalando ArgoCD..."
helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --values "${SCRIPT_DIR}/argocd-values.yaml" \
    --wait \
    --timeout 5m

log_success "ArgoCD instalado"
echo ""

# Install Argo Rollouts
log_step "[3/4] Instalando Argo Rollouts..."
helm upgrade --install argo-rollouts argo/argo-rollouts \
    --namespace argo-rollouts \
    --set controller.metrics.enabled=true \
    --set controller.metrics.serviceMonitor.enabled=true \
    --set controller.metrics.serviceMonitor.additionalLabels.release=prometheus \
    --set dashboard.enabled=true \
    --wait \
    --timeout 5m

log_success "Argo Rollouts instalado"
echo ""

# Patch NGINX Ingress Controller for metrics (if installed)
log_step "[4/4] Verificando NGINX Ingress Controller..."

if kubectl get deployment ingress-nginx-controller -n ingress-nginx &>/dev/null; then
    log_info "NGINX Ingress Controller encontrado, habilitando métricas..."
    
    # Add prometheus scraping annotations
    kubectl patch deployment ingress-nginx-controller -n ingress-nginx --type merge -p '{
      "spec": {
        "template": {
          "metadata": {
            "annotations": {
              "prometheus.io/scrape": "true",
              "prometheus.io/port": "10254"
            }
          }
        }
      }
    }' 2>/dev/null || log_warn "Não foi possível adicionar anotações"
    
    # Add prometheus port
    kubectl patch deployment ingress-nginx-controller -n ingress-nginx --type json -p '[
      {
        "op": "add",
        "path": "/spec/template/spec/containers/0/ports/-",
        "value": {
          "name": "prometheus",
          "containerPort": 10254,
          "protocol": "TCP"
        }
      }
    ]' 2>/dev/null || log_warn "Porta prometheus pode já existir"
    
    # Check if metrics are enabled
    CURRENT_ARGS=$(kubectl get deployment ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null || echo "[]")
    if ! echo "$CURRENT_ARGS" | grep -q "enable-metrics"; then
        kubectl patch deployment ingress-nginx-controller -n ingress-nginx --type json -p '[
          {
            "op": "add",
            "path": "/spec/template/spec/containers/0/args/-",
            "value": "--enable-metrics=true"
          }
        ]' 2>/dev/null || log_warn "Não foi possível habilitar métricas"
    fi
    
    # Create metrics service
    cat <<EOF | kubectl apply -f - 2>/dev/null || log_warn "Service de métricas pode já existir"
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller-metrics
  namespace: ingress-nginx
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/instance: ingress-nginx
    app.kubernetes.io/component: controller
spec:
  type: ClusterIP
  ports:
    - name: prometheus
      port: 10254
      targetPort: prometheus
      protocol: TCP
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/instance: ingress-nginx
    app.kubernetes.io/component: controller
EOF
    
    # Create ServiceMonitor
    cat <<EOF | kubectl apply -f - 2>/dev/null || log_warn "ServiceMonitor pode já existir"
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: ingress-nginx
      app.kubernetes.io/instance: ingress-nginx
      app.kubernetes.io/component: controller
  endpoints:
    - port: prometheus
      interval: 15s
      scrapeTimeout: 10s
      path: /metrics
  namespaceSelector:
    matchNames:
      - ingress-nginx
EOF
    
    log_success "NGINX Ingress Controller métricas habilitadas"
else
    log_warn "NGINX Ingress Controller não encontrado (pular)"
fi

echo ""

# Wait for everything to be ready
log_step "Aguardando pods..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=120s || true
kubectl wait --for=condition=available deployment/argo-rollouts -n argo-rollouts --timeout=120s || true
kubectl wait --for=condition=available deployment/prometheus-kube-prometheus-stack-prometheus -n monitoring --timeout=120s || true

log_success "Todos os componentes prontos!"
echo ""

# Get credentials
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Instalação Completa!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# ArgoCD
PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "admin")
echo "ArgoCD:"
echo "  URL:      http://localhost:8081"
echo "  Username: admin"
echo "  Password: ${PASSWORD}"
echo "  Port-forward: kubectl port-forward svc/argocd-server -n argocd 8081:80"
echo ""

# Prometheus/Grafana
echo "Prometheus/Grafana:"
echo "  Prometheus URL: http://localhost:9090"
echo "  Grafana URL:    http://localhost:3000"
echo "  Grafana Login:  admin / admin"
echo "  Port-forward:   kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80"
echo ""

# Argo Rollouts Dashboard
echo "Argo Rollouts Dashboard:"
echo "  URL: http://localhost:3100"
echo "  Port-forward: kubectl port-forward svc/argo-rollouts-dashboard -n argo-rollouts 3100:3100"
echo ""

echo "Próximos passos:"
echo "  1. Instalar Kargo: ./setup/install.sh"
echo "  2. Aplicar recursos: kubectl apply -k base/"
echo ""

# Save credentials
creds_file="${SCRIPT_DIR}/.argocd-credentials"
cat > "$creds_file" << EOF
ARGOCD_URL=http://localhost:8081
ARGOCD_USERNAME=admin
ARGOCD_PASSWORD=${PASSWORD}
GRAFANA_URL=http://localhost:3000
GRAFANA_USERNAME=admin
GRAFANA_PASSWORD=admin
EOF
chmod 600 "$creds_file"
log_info "Credenciais salvas em: ${creds_file}"
