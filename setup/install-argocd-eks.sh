#!/bin/bash

set -e

echo "================================================"
echo "Installing ArgoCD on EKS Cluster (HA Mode)"
echo "================================================"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

# Check if we're connected to the right cluster
CLUSTER_NAME=$(kubectl config current-context | grep -o 'argocd-training' || echo "")
if [ -z "$CLUSTER_NAME" ]; then
    print_error "Not connected to argocd-training cluster"
    exit 1
fi

print_success "Connected to cluster: $(kubectl config current-context)"

# Add ArgoCD Helm repository
print_info "Adding ArgoCD Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

print_success "Helm repository added"

# Create ArgoCD namespace
print_info "Creating argocd namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Create HA values file for Helm
print_info "Creating Helm values for HA installation..."
cat > /tmp/argocd-ha-values.yaml <<EOF
global:
  domain: argocd.example.com

configs:
  params:
    server.insecure: true

# Redis HA for scalability
redis-ha:
  enabled: true
  haproxy:
    enabled: true
    replicas: 3
    metrics:
      enabled: true

# Controller - HA setup
controller:
  replicas: 2
  env:
    - name: ARGOCD_RECONCILIATION_TIMEOUT
      value: "180s"
  metrics:
    enabled: true
    serviceMonitor:
      enabled: false
  resources:
    limits:
      cpu: 2000m
      memory: 2Gi
    requests:
      cpu: 500m
      memory: 1Gi

# Server - HA setup
server:
  replicas: 3
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 5
  metrics:
    enabled: true
    serviceMonitor:
      enabled: false
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 128Mi
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
      service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
  ingress:
    enabled: false

# Repo Server - HA setup
repoServer:
  replicas: 3
  autoscaling:
    enabled: true
    minReplicas: 3
    maxReplicas: 5
  metrics:
    enabled: true
    serviceMonitor:
      enabled: false
  resources:
    limits:
      cpu: 1000m
      memory: 1Gi
    requests:
      cpu: 250m
      memory: 256Mi

# Application Controller
applicationSet:
  replicas: 2
  metrics:
    enabled: true
    serviceMonitor:
      enabled: false

# Notifications Controller
notifications:
  enabled: true
  argocdUrl: http://argocd.example.com
  metrics:
    enabled: true
    serviceMonitor:
      enabled: false

# Dex (OIDC)
dex:
  enabled: true
  metrics:
    enabled: true
    serviceMonitor:
      enabled: false
EOF

# Install ArgoCD using Helm
print_info "Installing ArgoCD in HA mode (this may take a few minutes)..."
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --values /tmp/argocd-ha-values.yaml \
  --wait \
  --timeout 10m

print_success "ArgoCD Helm chart installed"

# Wait for all components to be ready
print_info "Waiting for ArgoCD components to be ready..."

kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd
kubectl wait --for=condition=available --timeout=600s deployment/argocd-repo-server -n argocd
kubectl wait --for=condition=available --timeout=600s deployment/argocd-applicationset-controller -n argocd

print_success "All ArgoCD components are ready!"

# Get initial admin password
print_info "Retrieving initial admin password..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "")

if [ -z "$ARGOCD_PASSWORD" ]; then
    print_info "Waiting for initial admin secret to be created..."
    sleep 10
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
fi

# Get LoadBalancer URL
print_info "Getting ArgoCD server URL..."
sleep 10
ARGOCD_URL=""
for i in {1..30}; do
    ARGOCD_URL=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [ -n "$ARGOCD_URL" ]; then
        break
    fi
    echo "Waiting for LoadBalancer to be provisioned... ($i/30)"
    sleep 10
done

# Display access information
echo ""
echo "================================================"
print_success "ArgoCD HA Installation Complete!"
echo "================================================"
echo ""
echo "Access Information:"
if [ -n "$ARGOCD_URL" ]; then
    echo "  URL: http://${ARGOCD_URL}"
else
    print_info "LoadBalancer is still provisioning. Get the URL with:"
    echo "  kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
fi
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"
echo ""
echo "Architecture:"
echo "  - ArgoCD Server: 3 replicas (autoscaling enabled)"
echo "  - Repo Server: 3 replicas (autoscaling enabled)"
echo "  - Application Controller: 2 replicas"
echo "  - ApplicationSet Controller: 2 replicas"
echo "  - Redis HA: Enabled with HAProxy"
echo ""
echo "Login via CLI:"
if [ -n "$ARGOCD_URL" ]; then
    echo "  argocd login ${ARGOCD_URL} --username admin --password '${ARGOCD_PASSWORD}' --insecure"
fi
echo ""
echo "Check deployment status:"
echo "  kubectl get pods -n argocd"
echo "  kubectl get svc -n argocd"
echo ""
