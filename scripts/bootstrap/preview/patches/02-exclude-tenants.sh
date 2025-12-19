#!/bin/bash
# Exclude Tenants in Preview Mode
# Removes tenant applications (11-*) from root.yaml include pattern in preview mode
# Tenants require production secrets that don't exist in preview environments

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

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
    echo -e "${YELLOW}NOTE: This script is now deprecated.${NC}"
    echo -e "${BLUE}Tenant exclusion is now handled by the overlay structure.${NC}"
    echo -e "${BLUE}Preview overlay in bootstrap/overlays/preview only includes base components.${NC}"
    echo -e "${BLUE}Tenant components are in bootstrap/components-tenants/ and not included in base.${NC}"
    echo -e "${GREEN}✓ No action needed - tenants are automatically excluded from preview mode${NC}"
fi

exit 0
