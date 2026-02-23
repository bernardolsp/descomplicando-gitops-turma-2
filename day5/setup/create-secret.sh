#!/bin/bash
#
# create-secret.sh
# Cria um Secret de credenciais GitHub para o Kargo interativamente
#
# Usage: ./create-secret.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Criar Secret de Credenciais Git${NC}"
echo -e "${GREEN}  para Kargo${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl não encontrado"
    exit 1
fi

# Get GitHub info
echo -e "${CYAN}Configuração do GitHub${NC}"
echo ""

# Repository URL
read -p "URL do repositório GitHub (ex: https://github.com/usuario/repo): " REPO_URL

if [ -z "$REPO_URL" ]; then
    log_error "URL do repositório é obrigatória"
    exit 1
fi

# Validate URL format
if [[ ! "$REPO_URL" =~ ^https://github\.com/ ]]; then
    log_warn "URL não parece ser do GitHub (deve começar com https://github.com/)"
    read -p "Continuar mesmo assim? (s/N): " confirm
    if [[ ! $confirm =~ ^[Ss]$ ]]; then
        exit 0
    fi
fi

# Username (optional, default to extracting from URL)
DEFAULT_USER=$(echo "$REPO_URL" | sed -n 's|https://github.com/\([^/]*\)/.*|\1|p')
read -p "Username GitHub [${DEFAULT_USER}]: " USERNAME
USERNAME=${USERNAME:-$DEFAULT_USER}

if [ -z "$USERNAME" ]; then
    log_error "Username é obrigatório"
    exit 1
fi

# Personal Access Token
echo ""
echo -e "${YELLOW}Personal Access Token (PAT):${NC}"
echo "  1. Acesse: GitHub → Settings → Developer settings → Personal access tokens"
echo "  2. Gere um token com scope 'repo'"
echo "  3. Cole o token abaixo (não será exibido na tela)"
echo ""

read -s -p "Token: " TOKEN
echo ""

if [ -z "$TOKEN" ]; then
    log_error "Token é obrigatório"
    exit 1
fi

# Regex option
echo ""
read -p "Usar regex para múltiplos repositórios? (s/N): " USE_REGEX

if [[ $USE_REGEX =~ ^[Ss]$ ]]; then
    log_info "Regex habilitado"
    log_info "O token funcionará para todos os repositórios sob: https://github.com/${USERNAME}/"
    REPO_URL="https://github.com/${USERNAME}/.*"
    REPO_IS_REGEX="true"
else
    REPO_IS_REGEX="false"
fi

# Namespace
NAMESPACE="kargo-shared-resources"

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log_warn "Namespace '$NAMESPACE' não existe"
    read -p "Criar namespace? (S/n): " CREATE_NS
    if [[ ! $CREATE_NS =~ ^[Nn]$ ]]; then
        kubectl create namespace "$NAMESPACE"
        log_success "Namespace '$NAMESPACE' criado"
    else
        read -p "Namespace alternativo: " ALT_NS
        if [ -n "$ALT_NS" ]; then
            NAMESPACE="$ALT_NS"
        else
            log_error "Namespace é obrigatório"
            exit 1
        fi
    fi
fi

# Secret name (auto-generate or custom)
DEFAULT_SECRET_NAME="github-creds-${USERNAME}"
read -p "Nome do Secret [${DEFAULT_SECRET_NAME}]: " SECRET_NAME
SECRET_NAME=${SECRET_NAME:-$DEFAULT_SECRET_NAME}

echo ""
log_step "Resumo da configuração:"
echo "  Secret:      ${SECRET_NAME}"
echo "  Namespace:   ${NAMESPACE}"
echo "  Repo URL:    ${REPO_URL}"
echo "  Username:    ${USERNAME}"
echo "  Regex:       ${REPO_IS_REGEX}"
echo ""

read -p "Criar Secret? (S/n): " CONFIRM
if [[ $CONFIRM =~ ^[Nn]$ ]]; then
    log_info "Operação cancelada"
    exit 0
fi

# Base64 encode values
REPO_URL_B64=$(echo -n "$REPO_URL" | base64)
USERNAME_B64=$(echo -n "$USERNAME" | base64)
TOKEN_B64=$(echo -n "$TOKEN" | base64)

# Create Secret
echo ""
log_step "Criando Secret..."

if [ "$REPO_IS_REGEX" = "true" ]; then
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
  labels:
    kargo.akuity.io/cred-type: git
data:
  repoURL: ${REPO_URL_B64}
  repoURLIsRegex: "dHJ1ZQ=="
  username: ${USERNAME_B64}
  password: ${TOKEN_B64}
EOF
else
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
  labels:
    kargo.akuity.io/cred-type: git
data:
  repoURL: ${REPO_URL_B64}
  username: ${USERNAME_B64}
  password: ${TOKEN_B64}
EOF
fi

log_success "Secret '${SECRET_NAME}' criado no namespace '${NAMESPACE}'"

# Verify
echo ""
log_step "Verificando..."
kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" -o yaml | grep -E "(name:|labels:|cred-type)" | head -10

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Secret criado com sucesso!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "O Kargo vai encontrar automaticamente este Secret"
echo "quando precisar acessar o repositório:"
echo "  ${REPO_URL}"
echo ""
echo "Para verificar todos os secrets de credenciais:"
echo "  kubectl get secrets -n ${NAMESPACE} -l kargo.akuity.io/cred-type=git"
echo ""
