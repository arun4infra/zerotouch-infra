#!/bin/bash
# Optimize Crossplane resources for preview mode
# Reduces CPU and memory usage for Crossplane operator

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
    echo -e "${BLUE}Optimizing Crossplane resources for preview mode...${NC}"
    
    CROSSPLANE_FILE="$REPO_ROOT/bootstrap/argocd/base/01-crossplane.yaml"
    
    if [ -f "$CROSSPLANE_FILE" ]; then
        # Reduce Crossplane operator resources
        if grep -q "cpu: \"100m\"" "$CROSSPLANE_FILE" 2>/dev/null; then
            sed -i.bak 's/cpu: "100m"/cpu: "50m"/g' "$CROSSPLANE_FILE"
            sed -i.bak 's/cpu: "1000m"/cpu: "500m"/g' "$CROSSPLANE_FILE"
            sed -i.bak 's/memory: "256Mi"/memory: "128Mi"/g' "$CROSSPLANE_FILE"
            sed -i.bak 's/memory: "2Gi"/memory: "1Gi"/g' "$CROSSPLANE_FILE"
            rm -f "$CROSSPLANE_FILE.bak"
            echo -e "  ${GREEN}✓${NC} Reduced Crossplane resources (50m CPU, 128Mi memory)"
        fi
        
        echo -e "${GREEN}✓ Crossplane optimization complete${NC}"
    else
        echo -e "${YELLOW}⚠${NC} Crossplane file not found: $CROSSPLANE_FILE"
    fi
else
    echo -e "${YELLOW}⊘${NC} Not in preview mode, skipping Crossplane optimization"
fi

exit 0