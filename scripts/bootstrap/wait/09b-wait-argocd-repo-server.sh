#!/bin/bash
# Wait for ArgoCD repo server to be responsive
# Usage: ./09b-wait-argocd-repo-server.sh [--timeout seconds] [--namespace namespace]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
TIMEOUT=120
CHECK_INTERVAL=3
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
echo -e "${BLUE}║   Waiting for ArgoCD Repo Server to be Responsive           ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}⏳ Waiting for ArgoCD repo server to be responsive (timeout: ${TIMEOUT}s)...${NC}"
echo -e "${BLUE}Namespace: $ARGOCD_NAMESPACE${NC}"
echo ""

ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    echo -e "${BLUE}=== Checking repo server connectivity (${ELAPSED}s / ${TIMEOUT}s) ===${NC}"
    
    # Check if repo server deployment exists
    if ! kubectl get deployment argocd-repo-server -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
        echo -e "${YELLOW}⏳ ArgoCD repo server deployment not found${NC}"
        sleep $CHECK_INTERVAL
        ELAPSED=$((ELAPSED + CHECK_INTERVAL))
        continue
    fi
    
    # Check if repo server pod is ready
    REPO_POD_READY=$(kubectl get pods -n "$ARGOCD_NAMESPACE" -l app.kubernetes.io/name=argocd-repo-server -o json 2>/dev/null | jq '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length' 2>/dev/null || echo "0")
    
    if [[ "$REPO_POD_READY" -eq 0 ]]; then
        echo -e "${YELLOW}⏳ ArgoCD repo server pod not ready yet${NC}"
        sleep $CHECK_INTERVAL
        ELAPSED=$((ELAPSED + CHECK_INTERVAL))
        continue
    fi
    
    # Test repo server connectivity (port 8081)
    echo -e "${BLUE}Testing repo server connectivity on port 8081...${NC}"
    if kubectl exec -n "$ARGOCD_NAMESPACE" deployment/argocd-repo-server -- sh -c "timeout 5 bash -c '</dev/tcp/localhost/8081'" 2>/dev/null; then
        echo -e "${GREEN}✓ Repo server is responsive on port 8081${NC}"
        
        # Test repo server health endpoint (port 8084)
        echo -e "${BLUE}Testing repo server health endpoint on port 8084...${NC}"
        if kubectl exec -n "$ARGOCD_NAMESPACE" deployment/argocd-repo-server -- sh -c "timeout 5 bash -c '</dev/tcp/localhost/8084'" 2>/dev/null; then
            echo -e "${GREEN}✓ Repo server health endpoint is responsive${NC}"
        else
            echo -e "${YELLOW}⚠️  Repo server health endpoint not responsive (but continuing)${NC}"
        fi
        
        # Final validation - try to test ArgoCD API functionality
        echo -e "${BLUE}Validating ArgoCD functionality...${NC}"
        if kubectl get applications -n "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ ArgoCD API is functional${NC}"
        else
            echo -e "${YELLOW}⚠️  ArgoCD API not fully functional yet (but repo server is ready)${NC}"
        fi
        
        echo ""
        echo -e "${GREEN}✓ ArgoCD repo server is ready and responsive!${NC}"
        echo ""
        exit 0
    else
        echo -e "${YELLOW}⏳ Repo server not responsive on port 8081${NC}"
    fi
    
    echo ""
    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
done

# Timeout reached
echo ""
echo -e "${RED}✗ Timeout waiting for ArgoCD repo server to be responsive${NC}"
echo ""

echo -e "${YELLOW}Troubleshooting information:${NC}"
echo ""

# Show repo server pod status
echo -e "${BLUE}Repo Server Pod Status:${NC}"
kubectl get pods -n "$ARGOCD_NAMESPACE" -l app.kubernetes.io/name=argocd-repo-server 2>/dev/null || echo "Failed to get repo server pods"

echo ""
echo -e "${BLUE}Repo Server Service Status:${NC}"
kubectl get svc -n "$ARGOCD_NAMESPACE" argocd-repo-server 2>/dev/null || echo "Failed to get repo server service"

echo ""
echo -e "${YELLOW}Troubleshooting commands:${NC}"
echo "  kubectl logs -n $ARGOCD_NAMESPACE deployment/argocd-repo-server"
echo "  kubectl describe pod -n $ARGOCD_NAMESPACE -l app.kubernetes.io/name=argocd-repo-server"
echo "  kubectl port-forward -n $ARGOCD_NAMESPACE svc/argocd-repo-server 8081:8081"
echo ""

exit 1