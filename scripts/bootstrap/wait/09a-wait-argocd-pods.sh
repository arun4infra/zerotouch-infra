#!/bin/bash
# Wait for ArgoCD pods to be ready
# Usage: ./09a-wait-argocd-pods.sh [--timeout seconds] [--namespace namespace]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
TIMEOUT=300
CHECK_INTERVAL=5
ARGOCD_NAMESPACE="argocd"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --namespace)
            ARGOCD_NAMESPACE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--timeout seconds] [--namespace namespace]"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Waiting for ArgoCD Pods to be Ready                       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}⏳ Waiting for ArgoCD pods to be ready (timeout: ${TIMEOUT}s)...${NC}"
echo -e "${BLUE}Namespace: $ARGOCD_NAMESPACE${NC}"
echo ""

ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    echo -e "${BLUE}=== Checking ArgoCD pods (${ELAPSED}s / ${TIMEOUT}s) ===${NC}"
    
    # Check if namespace exists
    if ! kubectl get namespace "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
        echo -e "${YELLOW}⏳ Namespace '$ARGOCD_NAMESPACE' not found${NC}"
        sleep $CHECK_INTERVAL
        ELAPSED=$((ELAPSED + CHECK_INTERVAL))
        continue
    fi
    
    # Get pod counts
    TOTAL_PODS=$(kubectl get pods -n "$ARGOCD_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    
    if [[ "$TOTAL_PODS" -eq 0 ]]; then
        echo -e "${YELLOW}⏳ No ArgoCD pods found yet${NC}"
        sleep $CHECK_INTERVAL
        ELAPSED=$((ELAPSED + CHECK_INTERVAL))
        continue
    fi
    
    # Check ready pods
    READY_PODS=$(kubectl get pods -n "$ARGOCD_NAMESPACE" -o json 2>/dev/null | jq '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length' 2>/dev/null || echo "0")
    
    echo -e "${BLUE}ArgoCD pods: $READY_PODS/$TOTAL_PODS ready${NC}"
    
    if [[ "$READY_PODS" -eq "$TOTAL_PODS" ]]; then
        echo ""
        echo -e "${GREEN}✓ All ArgoCD pods are ready!${NC}"
        echo ""
        
        # Show final status
        echo -e "${BLUE}Pod Status:${NC}"
        kubectl get pods -n "$ARGOCD_NAMESPACE" -o wide
        echo ""
        exit 0
    fi
    
    # Show which pods are not ready
    echo -e "${YELLOW}Not ready pods:${NC}"
    kubectl get pods -n "$ARGOCD_NAMESPACE" -o json 2>/dev/null | jq -r '.items[] | select(.status.conditions[] | select(.type=="Ready" and .status!="True")) | "  - \(.metadata.name) (\(.status.phase))"' | head -5
    
    echo ""
    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
done

# Timeout reached
echo ""
echo -e "${RED}✗ Timeout waiting for ArgoCD pods to be ready${NC}"
echo ""
echo -e "${YELLOW}Final pod status:${NC}"
kubectl get pods -n "$ARGOCD_NAMESPACE" 2>/dev/null || echo "Failed to get pods"

echo ""
echo -e "${YELLOW}Troubleshooting commands:${NC}"
echo "  kubectl get pods -n $ARGOCD_NAMESPACE"
echo "  kubectl describe pods -n $ARGOCD_NAMESPACE"
echo "  kubectl logs -n $ARGOCD_NAMESPACE -l app.kubernetes.io/name=argocd-server"
echo ""

exit 1