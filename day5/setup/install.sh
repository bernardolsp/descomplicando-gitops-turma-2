#!/bin/bash
#
# install.sh - Instala o Kargo no cluster
#

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Instalando Kargo${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check prerequisites
echo "[1/5] Verificando pré-requisitos..."

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Erro: kubectl não encontrado${NC}"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo -e "${RED}Erro: Helm não encontrado${NC}"
    exit 1
fi

if ! command -v htpasswd &> /dev/null; then
    echo -e "${YELLOW}Aviso: htpasswd não encontrado. Instalando via brew...${NC}"
    brew install httpd 2>/dev/null || true
fi

echo -e "${GREEN}✓ Pré-requisitos OK${NC}"

# Install cert-manager if needed
echo "[2/5] Verificando cert-manager..."
if ! kubectl get namespace cert-manager &> /dev/null; then
    echo "Instalando cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
    kubectl wait --for=condition=available deployment/cert-manager -n cert-manager --timeout=120s || true
fi
echo -e "${GREEN}✓ cert-manager OK${NC}"

# Generate credentials
echo "[3/5] Gerando credenciais..."
password=$(openssl rand -base64 48 | tr -d "=+/" | head -c 32)
hashed_pass=$(htpasswd -bnBC 10 "" "$password" | tr -d ':\n')
signing_key=$(openssl rand -base64 48 | tr -d "=+/" | head -c 32)

# Save credentials
creds_file="${SCRIPT_DIR}/../.kargo-credentials"
cat > "$creds_file" << EOF
# Kargo Credentials
KARGO_URL=http://localhost:8080
KARGO_USERNAME=admin
KARGO_PASSWORD=${password}
EOF
chmod 600 "$creds_file"

echo -e "${GREEN}✓ Credenciais geradas${NC}"

# Install Kargo
echo "[4/5] Instalando Kargo..."
helm upgrade --install kargo \
    oci://ghcr.io/akuity/kargo-charts/kargo \
    --namespace kargo \
    --create-namespace \
    --values "${SCRIPT_DIR}/values.yaml" \
    --set api.adminAccount.passwordHash="$hashed_pass" \
    --set api.adminAccount.tokenSigningKey="$signing_key" \
    --wait

echo -e "${GREEN}✓ Kargo instalado${NC}"

# Apply RBAC for ArgoCD integration
echo "[5/5] Configurando RBAC para integração com ArgoCD..."
kubectl apply -f "${SCRIPT_DIR}/kargo-argocd-rbac.yaml"

# Restart Kargo controller to pick up new RBAC
kubectl rollout restart deployment/kargo-controller -n kargo
kubectl rollout status deployment/kargo-controller -n kargo --timeout=60s

echo -e "${GREEN}✓ RBAC aplicado e controller reiniciado${NC}"

# Verify
echo "[6/6] Verificando instalação..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kargo -n kargo --timeout=60s || true
echo -e "${GREEN}✓ Kargo pronto${NC}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Instalação Completa!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Credenciais:"
echo "  Usuário: admin"
echo "  Senha: ${password}"
echo "  Arquivo: ${creds_file}"
echo ""
echo "Próximos passos:"
echo "  1. kubectl apply -k base/"
echo "  2. kubectl port-forward svc/kargo-api -n kargo 8080:80"
echo "  3. Abrir http://localhost:8080"
echo ""
