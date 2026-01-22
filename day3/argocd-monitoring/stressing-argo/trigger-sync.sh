#!/bin/bash
set -e

BATCH_SIZE=${BATCH_SIZE:-50}
DELAY=${DELAY:-1}
NAMESPACE="argocd"
LABEL="app.kubernetes.io/part-of=stress-test"
MODE="refresh"  # refresh, sync, or chaos

while [[ $# -gt 0 ]]; do
    case $1 in
        --batch-size) BATCH_SIZE="$2"; shift 2 ;;
        --delay) DELAY="$2"; shift 2 ;;
        --mode) MODE="$2"; shift 2 ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --batch-size N   Apps per batch (default: 50)"
            echo "  --delay S        Seconds between batches (default: 1)"
            echo "  --mode MODE      Mode: refresh, sync, chaos (default: refresh)"
            echo ""
            echo "Modes:"
            echo "  refresh  - Hard refresh (re-fetch manifests from git)"
            echo "  sync     - Force sync operation on each app"
            echo "  chaos    - Randomize app config to force real changes"
            exit 0 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

echo "=== Trigger Sync em Massa ==="
echo "Mode: $MODE | Batch: $BATCH_SIZE | Delay: ${DELAY}s"

APPS=$(kubectl get applications -n "$NAMESPACE" -l "$LABEL" -o jsonpath='{.items[*].metadata.name}')
APP_ARRAY=($APPS)
TOTAL=${#APP_ARRAY[@]}

if [ $TOTAL -eq 0 ]; then
    echo "Nenhuma aplicação encontrada com label: $LABEL"
    exit 1
fi

echo "Encontradas $TOTAL aplicações"
echo ""

trigger_refresh() {
    local app=$1
    kubectl patch application "$app" -n "$NAMESPACE" --type=merge \
        -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' 2>/dev/null &
}

trigger_sync() {
    local app=$1
    # Set operation to sync with force
    kubectl patch application "$app" -n "$NAMESPACE" --type=merge \
        -p '{"operation":{"initiatedBy":{"username":"stress-test"},"sync":{"force":true,"prune":false}}}' 2>/dev/null &
}

trigger_chaos() {
    local app=$1
    local rand=$((RANDOM % 3 + 1))
    # Patch the app to change replicas - forces re-template
    kubectl patch application "$app" -n "$NAMESPACE" --type=json \
        -p "[{\"op\":\"replace\",\"path\":\"/spec/source/helm/valuesObject/nginx/replicas\",\"value\":$rand}]" 2>/dev/null &
}

PROCESSED=0
START=$(date +%s)

for APP in "${APP_ARRAY[@]}"; do
    case $MODE in
        refresh) trigger_refresh "$APP" ;;
        sync)    trigger_sync "$APP" ;;
        chaos)   trigger_chaos "$APP" ;;
    esac

    PROCESSED=$((PROCESSED + 1))

    if (( PROCESSED % BATCH_SIZE == 0 )); then
        wait
        NOW=$(date +%s)
        ELAPSED=$((NOW - START))
        echo "Progresso: $PROCESSED/$TOTAL (${ELAPSED}s)"
        sleep $DELAY
    fi
done

wait
END=$(date +%s)
TOTAL_TIME=$((END - START))

echo ""
echo "=== Completo: $PROCESSED apps em ${TOTAL_TIME}s ==="
echo ""
echo "Monitorar queue depth:"
echo "  watch -n1 'kubectl exec -n argocd deploy/argocd-application-controller -- sh -c \"cat /proc/1/status | grep -E Threads\"'"
echo ""
echo "Ou no Grafana - workqueue_depth deve subir!"
