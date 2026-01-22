#!/bin/bash
set -e

BATCH_SIZE=${BATCH_SIZE:-50}
DELAY=${DELAY:-2}
NAMESPACE="argocd"
LABEL="app.kubernetes.io/part-of=stress-test"

while [[ $# -gt 0 ]]; do
    case $1 in
        --batch-size) BATCH_SIZE="$2"; shift 2 ;;
        --delay) DELAY="$2"; shift 2 ;;
        --hard-refresh) HARD_REFRESH=true; shift ;;
        --help)
            echo "Usage: $0 [--batch-size N] [--delay S] [--hard-refresh]"
            exit 0 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

echo "=== Trigger Sync em Massa ==="
echo "Batch size: $BATCH_SIZE | Delay: ${DELAY}s"

APPS=$(kubectl get applications -n "$NAMESPACE" -l "$LABEL" -o jsonpath='{.items[*].metadata.name}')
APP_ARRAY=($APPS)
TOTAL=${#APP_ARRAY[@]}

if [ $TOTAL -eq 0 ]; then
    echo "Nenhuma aplicação encontrada com label: $LABEL"
    exit 1
fi

echo "Encontradas $TOTAL aplicações"

SYNCED=0
for APP in "${APP_ARRAY[@]}"; do
    TIMESTAMP=$(date +%s)
    kubectl patch application "$APP" -n "$NAMESPACE" --type=merge \
        -p "{\"metadata\":{\"annotations\":{\"argocd.argoproj.io/refresh\":\"$TIMESTAMP\"}}}" &

    SYNCED=$((SYNCED + 1))

    if (( SYNCED % BATCH_SIZE == 0 )); then
        wait
        echo "Progresso: $SYNCED/$TOTAL"
        sleep $DELAY
    fi
done

wait
echo ""
echo "=== Sync disparado em $TOTAL aplicações ==="
echo ""
echo "Monitorar:"
echo "  watch kubectl get applications -n $NAMESPACE -l $LABEL -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status"
