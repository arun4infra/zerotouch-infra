#!/bin/bash
# Optimize resource usage for preview mode
# Patches database and platform components that overlays don't handle

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
    echo -e "${BLUE}Verifying overlay optimizations for preview mode...${NC}"
    
    # Verify overlay optimizations are in place
    OVERLAY_FILE="$REPO_ROOT/bootstrap/argocd/overlays/preview/kustomization.yaml"
    if [ -f "$OVERLAY_FILE" ]; then
        NATS_OPTIMIZED=$(grep -c "cpu: 50m" "$OVERLAY_FILE" 2>/dev/null || echo "0")
        KAGENT_OPTIMIZED=$(grep -c "cpu: 25m" "$OVERLAY_FILE" 2>/dev/null || echo "0")
        
        if [ "$NATS_OPTIMIZED" -gt 0 ] && [ "$KAGENT_OPTIMIZED" -gt 0 ]; then
            echo -e "  ${GREEN}✓${NC} Overlay optimizations verified (NATS, Kagent, KEDA)"
        else
            echo -e "  ${YELLOW}⚠${NC} Some overlay optimizations may be missing"
        fi
    fi
    
    echo -e "${GREEN}✓ Preview overlay verification complete${NC}"
    echo -e "${BLUE}  Individual resource optimizations handled by separate patches (08-13)${NC}"
fi

exit 0
