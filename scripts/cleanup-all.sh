#!/bin/bash

set -e

echo "================================================"
echo "Cleanup All Environments"
echo "================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Warning
print_error "⚠️  WARNING: This will delete ALL clusters and resources!"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""

# Cleanup KinD cluster (Day 1)
if command -v kind &> /dev/null; then
    if kind get clusters | grep -q "^argocd-day1$"; then
        print_info "Deleting KinD cluster: argocd-day1..."
        kind delete cluster --name argocd-day1
        print_success "KinD cluster deleted"
    else
        print_info "KinD cluster argocd-day1 not found, skipping..."
    fi
fi

# Cleanup EKS cluster (Days 2-5)
if command -v eksctl &> /dev/null; then
    if eksctl get cluster --name argocd-training --region us-east-1 &> /dev/null; then
        print_info "Deleting EKS cluster: argocd-training (this will take ~10-15 minutes)..."

        # First, delete any LoadBalancers to avoid issues
        print_info "Cleaning up LoadBalancers..."
        if kubectl config get-contexts | grep -q "argocd-training"; then
            kubectl delete svc --all -n argocd --ignore-not-found=true
            sleep 30
        fi

        # Delete cluster
        eksctl delete cluster --name argocd-training --region us-east-1 --wait
        print_success "EKS cluster deleted"
    else
        print_info "EKS cluster argocd-training not found, skipping..."
    fi
fi

# Cleanup additional KinD clusters (if any from multi-cluster labs)
if command -v kind &> /dev/null; then
    for cluster in $(kind get clusters); do
        if [[ $cluster == *"argocd"* ]] || [[ $cluster == *"cluster"* ]]; then
            print_info "Deleting additional KinD cluster: $cluster..."
            kind delete cluster --name "$cluster"
            print_success "Cluster $cluster deleted"
        fi
    done
fi

# Cleanup Docker containers
print_info "Cleaning up Docker containers..."
docker container prune -f &> /dev/null || true
print_success "Docker containers cleaned"

# Cleanup Docker images (optional - commented out to avoid deleting useful images)
# print_info "Cleaning up Docker images..."
# docker image prune -a -f &> /dev/null || true
# print_success "Docker images cleaned"

# Remove kubeconfig contexts
print_info "Cleaning up kubeconfig contexts..."
kubectl config delete-context kind-argocd-day1 &> /dev/null || true
kubectl config delete-context arn:aws:eks:us-east-1:*:cluster/argocd-training &> /dev/null || true
print_success "Kubeconfig cleaned"

# Remove temporary files
print_info "Cleaning up temporary files..."
rm -f /tmp/argocd-ha-values.yaml
rm -f /tmp/iam_policy.json
rm -f /tmp/awscliv2.zip
rm -f /tmp/AWSCLIV2.pkg
print_success "Temporary files cleaned"

echo ""
echo "================================================"
print_success "Cleanup Complete!"
echo "================================================"
echo ""
echo "All clusters and resources have been deleted."
echo ""
echo "To start fresh:"
echo "  Day 1: ./setup/create-kind-cluster.sh"
echo "  Days 2-5: ./setup/create-eks-cluster.sh"
echo ""
