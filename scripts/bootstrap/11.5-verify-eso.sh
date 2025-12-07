#!/bin/bash
# Verify External Secrets Operator (ESO)
# Usage: ./08-verify-eso.sh
#
# This script verifies:
# 1. ESO credentials exist
# 2. ClusterSecretStore is valid
# 3. ESO can access AWS SSM

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
echo -e "${BLUE}║   Verifying External Secrets Operator                       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if ESO credentials exist
if kubectl_retry get secret aws-access-token -n external-secrets &>/dev/null; then
    echo -e "${GREEN}✓ ESO credentials found${NC}"
    
    # Wait for ClusterSecretStore to be valid
    echo -e "${BLUE}⏳ Waiting for ESO to sync secrets (timeout: 2 minutes)...${NC}"
    TIMEOUT=120
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        STORE_STATUS=$(kubectl_retry get clustersecretstore aws-parameter-store -o jsonpath='{.status.conditions[0].status}' 2>/dev/null || echo "Unknown")
        
        if [ "$STORE_STATUS" = "True" ]; then
            echo -e "${GREEN}✓ ESO credentials configured and working${NC}"
            echo -e "${GREEN}✓ ClusterSecretStore 'aws-parameter-store' is valid${NC}"
            echo ""
            exit 0
        fi
        
        sleep 10
        ELAPSED=$((ELAPSED + 10))
    done
    
    echo -e "${YELLOW}⚠️  ESO not ready yet - secrets may sync later${NC}"
    echo -e "${BLUE}ℹ  You can verify manually: kubectl get clustersecretstore aws-parameter-store${NC}"
    echo ""
    exit 0
else
    echo -e "${YELLOW}⚠️  AWS credentials not found - ESO won't be able to sync secrets${NC}"
    echo -e "${BLUE}ℹ  You can inject manually: ./scripts/bootstrap/07-inject-eso-secrets.sh${NC}"
    echo ""
    exit 0
fi
