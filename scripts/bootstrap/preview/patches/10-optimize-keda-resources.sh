#!/bin/bash
# Optimize KEDA resources for preview mode
# Reduces CPU and memory usage for KEDA operator

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Find repository root by looking for .git directory
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR" && while [[ ! -d .git && $(pwd) != "/" ]]; do cd ..; done; pwd))"

FORCE_UPDATE=false

# Parse arguments
if [ "$1" = "--force" ]; then
    FORCE_UPDATE=true
fi

# Check if this is preview mode
IS_PREVIEW_MODE=false

if [ "$FORCE_UPDATE" = true ]; then
    IS_PREVIEW_MODE=true
elif command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
    if ! kubectl get nodes -o jsonpath='{.items[*].spec.taints[?(@.key=="node-role.kubernetes.io/control-plane")]}' 2>/dev/null | grep -q "control-plane"; then
        IS_PREVIEW_MODE=true
    fi
fi

if [ "$IS_PREVIEW_MODE" = true ]; then
    echo -e "${BLUE}Optimizing KEDA resources for preview mode...${NC}"
    
    KEDA_FILE="$REPO_ROOT/bootstrap/argocd/base/01-keda.yaml"
    
    if [ -f "$KEDA_FILE" ]; then
        # Reduce KEDA operator resources
        if grep -q "cpu: 100m" "$KEDA_FILE" 2>/dev/null; then
            sed -i.bak 's/cpu: 100m/cpu: 50m/g' "$KEDA_FILE"
            sed -i.bak 's/cpu: 1000m/cpu: 500m/g' "$KEDA_FILE"
            sed -i.bak 's/memory: 256Mi/memory: 128Mi/g' "$KEDA_FILE"
            sed -i.bak 's/memory: 1000Mi/memory: 512Mi/g' "$KEDA_FILE"
            rm -f "$KEDA_FILE.bak"
            echo -e "  ${GREEN}✓${NC} Reduced KEDA resources (50m CPU, 128Mi memory)"
        fi
        
        echo -e "${GREEN}✓ KEDA optimization complete${NC}"
    else
        echo -e "${YELLOW}⚠${NC} KEDA file not found: $KEDA_FILE"
    fi
else
    echo -e "${YELLOW}⊘${NC} Not in preview mode, skipping KEDA optimization"
fi

exit 0