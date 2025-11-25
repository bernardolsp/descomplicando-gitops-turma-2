#!/bin/bash

set -e

echo "================================================"
echo "Installing ArgoCD on KinD Cluster"
echo "================================================"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: Cannot connect to Kubernetes cluster"
    exit 1
fi

# Create ArgoCD namespace
print_info "Creating argocd namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
print_info "Installing ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
print_info "Waiting for ArgoCD components to be ready..."
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd
kubectl wait --for=condition=available --timeout=600s deployment/argocd-repo-server -n argocd
kubectl wait --for=condition=available --timeout=600s deployment/argocd-dex-server -n argocd

print_success "ArgoCD components are ready!"

# Create Ingress for ArgoCD
print_info "Creating Ingress for ArgoCD..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
spec:
  ingressClassName: nginx
  rules:
  - host: argocd.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
EOF

print_success "Ingress created"

# Patch argocd-server to run with --insecure flag (for development)
print_info "Patching ArgoCD server for insecure mode..."
kubectl patch deployment argocd-server -n argocd --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/args", "value": ["/usr/local/bin/argocd-server", "--insecure"]}]'

# Wait for the server to restart
sleep 10
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

print_success "ArgoCD server patched"

# Get initial admin password
print_info "Retrieving initial admin password..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Display access information
echo ""
echo "================================================"
print_success "ArgoCD Installation Complete!"
echo "================================================"
echo ""
echo "Access Information:"
echo "  URL: http://argocd.local"
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"
echo ""
echo "To access ArgoCD:"
echo "  1. Add to /etc/hosts: echo '127.0.0.1 argocd.local' | sudo tee -a /etc/hosts"
echo "  2. Open browser: http://argocd.local"
echo ""
echo "Alternative access via port-forward:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:80"
echo "  Then access: http://localhost:8080"
echo ""
echo "Login via CLI:"
echo "  argocd login argocd.local --username admin --password ${ARGOCD_PASSWORD} --insecure"
echo ""
