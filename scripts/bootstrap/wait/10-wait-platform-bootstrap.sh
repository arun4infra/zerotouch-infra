#!/bin/bash
# Wait for Platform Bootstrap Application
# Usage: ./11-wait-platform-bootstrap.sh
#
# This script waits for the platform-bootstrap ArgoCD application
# to sync and become healthy

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Kubectl retry function
kubectl_retry() {
    local max_attempts=20
    local timeout=15
    local attempt=1
    local exitCode=0

    while [ $attempt -le $max_attempts ]; do
        if timeout $timeout kubectl "$@"; then
            return 0
        fi

        exitCode=$?

        if [ $attempt -lt $max_attempts ]; then
            local delay=$((attempt * 2))
            echo -e "${YELLOW}⚠️  kubectl command failed (attempt $attempt/$max_attempts). Retrying in ${delay}s...${NC}" >&2
            sleep $delay
        fi

        attempt=$((attempt + 1))
    done

    echo -e "${RED}✗ kubectl command failed after $max_attempts attempts${NC}" >&2
    return $exitCode
}

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Waiting for Platform Bootstrap                            ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}⏳ Waiting for platform-bootstrap to sync (timeout: 5 minutes)...${NC}"
TIMEOUT=300
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    # Check if platform-bootstrap application exists
    if kubectl_retry get application platform-bootstrap -n argocd >/dev/null 2>&1; then
        SYNC_STATUS=$(kubectl_retry get application platform-bootstrap -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        HEALTH_STATUS=$(kubectl_retry get application platform-bootstrap -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        
        echo -e "${BLUE}platform-bootstrap found: $SYNC_STATUS / $HEALTH_STATUS${NC}"
        
        if [ "$SYNC_STATUS" = "Synced" ] && [ "$HEALTH_STATUS" = "Healthy" ]; then
            echo -e "${GREEN}✓ platform-bootstrap synced successfully${NC}"
            echo ""
            exit 0
        fi
        
        # Show detailed error information EVERY time for non-healthy states
        if [ "$SYNC_STATUS" != "Synced" ] || [ "$HEALTH_STATUS" != "Healthy" ]; then
            echo -e "${YELLOW}   Investigating status: $SYNC_STATUS / $HEALTH_STATUS${NC}"
            
            # Get application JSON for detailed analysis
            APP_JSON=$(kubectl_retry get application platform-bootstrap -n argocd -o json 2>/dev/null || echo "{}")
            
            # Show error conditions
            CONDITIONS=$(echo "$APP_JSON" | jq -r '.status.conditions[]? | "     - \(.type): \(.message // "no message")"' 2>/dev/null)
            if [ -n "$CONDITIONS" ]; then
                echo -e "${YELLOW}   Conditions:${NC}"
                echo "$CONDITIONS"
            fi
            
            # Show operation state for sync errors
            OP_PHASE=$(echo "$APP_JSON" | jq -r '.status.operationState.phase // "none"' 2>/dev/null)
            OP_MSG=$(echo "$APP_JSON" | jq -r '.status.operationState.message // ""' 2>/dev/null)
            if [ "$OP_PHASE" != "none" ] && [ "$OP_PHASE" != "null" ]; then
                if [ "$OP_PHASE" = "Failed" ] || [ "$OP_PHASE" = "Error" ]; then
                    echo -e "${RED}   Operation: $OP_PHASE${NC}"
                    [ -n "$OP_MSG" ] && echo -e "${RED}   Message: ${OP_MSG:0:200}${NC}"
                else
                    echo -e "${BLUE}   Operation: $OP_PHASE${NC}"
                    [ -n "$OP_MSG" ] && echo -e "${BLUE}   Message: ${OP_MSG:0:100}${NC}"
                fi
            fi
            
            # Show source configuration to verify patch worked
            REPO_URL=$(echo "$APP_JSON" | jq -r '.spec.source.repoURL // "unknown"' 2>/dev/null)
            TARGET_REV=$(echo "$APP_JSON" | jq -r '.spec.source.targetRevision // "unknown"' 2>/dev/null)
            SOURCE_PATH=$(echo "$APP_JSON" | jq -r '.spec.source.path // "unknown"' 2>/dev/null)
            echo -e "${BLUE}   Source: $REPO_URL${NC}"
            echo -e "${BLUE}   Target: $TARGET_REV${NC}"
            echo -e "${BLUE}   Path: $SOURCE_PATH${NC}"
            
            # Show recent ArgoCD logs related to this app
            echo -e "${BLUE}   Recent repo server logs:${NC}"
            kubectl_retry logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=10 2>/dev/null | \
                grep -i "platform-bootstrap\|error\|failed\|unable to resolve" | tail -3 | \
                sed 's/^/     /' || echo "     No relevant logs found"
            
            echo ""
        fi
    else
        echo -e "${YELLOW}⚠️  platform-bootstrap application not found yet${NC}"
        
        # Show all applications for debugging
        echo -e "${BLUE}Current applications:${NC}"
        kubectl_retry get applications -n argocd -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status 2>/dev/null || echo "Failed to get applications"
        
        # Check platform-root status specifically
        if kubectl_retry get application platform-root -n argocd >/dev/null 2>&1; then
            ROOT_SYNC=$(kubectl_retry get application platform-root -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
            ROOT_HEALTH=$(kubectl_retry get application platform-root -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
            echo -e "${BLUE}platform-root status: $ROOT_SYNC / $ROOT_HEALTH${NC}"
            
            # Show platform-root sync details if it has issues
            if [ "$ROOT_SYNC" != "Synced" ]; then
                echo -e "${YELLOW}platform-root sync details:${NC}"
                kubectl_retry describe application platform-root -n argocd | grep -A 10 -B 5 "Sync\|Error\|Message" || echo "Failed to get details"
            fi
        fi
    fi
    
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

echo -e "${RED}✗ Timeout waiting for platform-bootstrap to sync${NC}"
echo ""
echo -e "${YELLOW}=== Final Debugging Information ===${NC}"

# Show final application status
if kubectl_retry get application platform-bootstrap -n argocd >/dev/null 2>&1; then
    echo -e "${BLUE}Final application status:${NC}"
    kubectl_retry describe application platform-bootstrap -n argocd || echo "Failed to describe application"
    echo ""
    
    echo -e "${BLUE}Application YAML:${NC}"
    kubectl_retry get application platform-bootstrap -n argocd -o yaml || echo "Failed to get application YAML"
    echo ""
else
    echo -e "${RED}platform-bootstrap application not found${NC}"
fi

# Show ArgoCD server logs for errors
echo -e "${BLUE}Recent ArgoCD server logs:${NC}"
kubectl_retry logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50 | grep -i "platform-bootstrap\|error\|failed" || echo "No relevant logs found"
echo ""

# Show ArgoCD repo server logs for errors  
echo -e "${BLUE}Recent ArgoCD repo server logs:${NC}"
kubectl_retry logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=50 | grep -i "platform-bootstrap\|error\|failed\|unable to resolve" || echo "No relevant logs found"
echo ""

echo -e "${YELLOW}Manual debugging commands:${NC}"
echo "kubectl describe application platform-bootstrap -n argocd"
echo "kubectl get application platform-bootstrap -n argocd -o yaml"
echo "kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=100"
echo "kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=100"
echo ""
exit 1
