#!/bin/bash
set -e

echo "=== Cleanup Stress Test ==="

read -p "Deletar todos os recursos de stress test? (y/N) " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Abortado."
    exit 0
fi

echo "Deletando ApplicationSet..."
kubectl delete applicationset stress-test -n argocd --ignore-not-found=true

echo "Deletando Applications restantes..."
kubectl delete applications -n argocd -l app.kubernetes.io/part-of=stress-test --ignore-not-found=true

echo "Deletando namespace stress-test..."
kubectl delete namespace stress-test --ignore-not-found=true

echo ""
echo "=== Cleanup Completo ==="
