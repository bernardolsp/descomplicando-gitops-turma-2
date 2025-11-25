#!/bin/bash

echo "================================================"
echo "Environment Validation Script"
echo "================================================"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

ERRORS=0

# Function to check command
check_command() {
    if command -v "$1" &> /dev/null; then
        VERSION=$($2)
        print_success "$1 is installed: $VERSION"
    else
        print_error "$1 is NOT installed"
        ((ERRORS++))
    fi
}

# Core tools
echo "Checking Core Tools..."
check_command "docker" "docker --version"
check_command "kubectl" "kubectl version --client --short 2>/dev/null || kubectl version --client"
check_command "helm" "helm version --short"
check_command "git" "git --version"
echo ""

# Day 1 tools
echo "Checking Day 1 Tools..."
check_command "kind" "kind version"
echo ""

# Days 2-5 tools
echo "Checking Days 2-5 Tools..."
check_command "eksctl" "eksctl version"
check_command "aws" "aws --version"
echo ""

# ArgoCD tools
echo "Checking ArgoCD Tools..."
check_command "argocd" "argocd version --client --short 2>/dev/null || echo 'ArgoCD CLI'"
echo ""

# Utility tools
echo "Checking Utility Tools..."
check_command "jq" "jq --version"
check_command "yq" "yq --version"
echo ""

# Check Docker daemon
echo "Checking Docker Daemon..."
if docker ps &> /dev/null; then
    print_success "Docker daemon is running"
else
    print_error "Docker daemon is NOT running"
    ((ERRORS++))
fi
echo ""

# Check AWS credentials (Days 2-5)
echo "Checking AWS Configuration..."
if command -v aws &> /dev/null; then
    if aws sts get-caller-identity &> /dev/null; then
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        REGION=$(aws configure get region || echo "not-set")
        print_success "AWS credentials are configured"
        echo "  Account ID: $ACCOUNT_ID"
        echo "  Region: $REGION"
    else
        print_info "AWS credentials are NOT configured (required for Days 2-5)"
        echo "  Run: aws configure"
    fi
else
    print_info "AWS CLI not installed (required for Days 2-5)"
fi
echo ""

# Check cluster (if any)
echo "Checking Kubernetes Clusters..."

# Check KinD clusters
if command -v kind &> /dev/null; then
    KIND_CLUSTERS=$(kind get clusters 2>/dev/null)
    if [ -n "$KIND_CLUSTERS" ]; then
        print_success "KinD clusters found:"
        echo "$KIND_CLUSTERS" | while read -r cluster; do
            echo "  - $cluster"
        done
    else
        print_info "No KinD clusters found"
    fi
else
    print_info "KinD not installed"
fi
echo ""

# Check current kubectl context
if kubectl cluster-info &> /dev/null; then
    CONTEXT=$(kubectl config current-context)
    print_success "kubectl is connected to: $CONTEXT"

    # Check ArgoCD
    if kubectl get namespace argocd &> /dev/null; then
        print_success "ArgoCD namespace exists"

        # Check ArgoCD pods
        ARGOCD_PODS=$(kubectl get pods -n argocd --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [ "$ARGOCD_PODS" -gt 0 ]; then
            print_success "ArgoCD pods running: $ARGOCD_PODS"

            # Check if all pods are ready
            NOT_READY=$(kubectl get pods -n argocd --no-headers 2>/dev/null | grep -v "Running" | wc -l | tr -d ' ')
            if [ "$NOT_READY" -eq 0 ]; then
                print_success "All ArgoCD pods are ready"
            else
                print_error "Some ArgoCD pods are not ready"
                kubectl get pods -n argocd
            fi
        else
            print_error "No ArgoCD pods found"
        fi
    else
        print_info "ArgoCD is not installed"
    fi
else
    print_info "No Kubernetes cluster is currently configured"
fi
echo ""

# Summary
echo "================================================"
if [ $ERRORS -eq 0 ]; then
    print_success "Environment validation completed successfully!"
else
    print_error "Environment validation found $ERRORS error(s)"
    echo ""
    echo "Please run: ./setup/install-prerequisites.sh"
fi
echo "================================================"
echo ""

exit $ERRORS
