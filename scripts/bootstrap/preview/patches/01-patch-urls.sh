#!/bin/bash
# Ensure Preview URLs Helper
# Ensures ArgoCD applications use local filesystem URLs in preview mode
# Can be called with --force to skip cluster detection

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

echo -e "${BLUE}Script directory: $SCRIPT_DIR${NC}"
echo -e "${BLUE}Repository root: $REPO_ROOT${NC}"

FORCE_UPDATE=false

# Parse arguments
if [ "$1" = "--force" ]; then
    FORCE_UPDATE=true
fi

# Check if this is preview mode (either forced or Kind cluster detected)
IS_PREVIEW_MODE=false

if [ "$FORCE_UPDATE" = true ]; then
    IS_PREVIEW_MODE=true
elif command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
    # Check if this is a Kind cluster (no control-plane taints)
    if ! kubectl get nodes -o jsonpath='{.items[*].spec.taints[?(@.key=="node-role.kubernetes.io/control-plane")]}' 2>/dev/null | grep -q "control-plane"; then
        IS_PREVIEW_MODE=true
    fi
fi

if [ "$IS_PREVIEW_MODE" = true ]; then
    echo -e "${YELLOW}NOTE: This script is now deprecated.${NC}"
    echo -e "${BLUE}URL patching is now handled by Kustomize overlays in bootstrap/overlays/preview${NC}"
    echo -e "${GREEN}✓ No action needed - overlays will handle URL patching automatically${NC}"
fi

exit 0