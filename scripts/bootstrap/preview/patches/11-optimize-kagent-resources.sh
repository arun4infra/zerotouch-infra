#!/bin/bash
# Optimize Kagent resources for preview mode
# Disables Kagent completely for preview environments (not needed for testing)

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
    echo -e "${BLUE}Optimizing Kagent resources for preview mode...${NC}"
    
    # Find all Kagent claim files across the platform
    KAGENT_FILES=$(find "$REPO_ROOT" -type f -name "*kagent*.yaml" -path "*/platform/claims/*" 2>/dev/null || true)
    
    if [ -z "$KAGENT_FILES" ]; then
        echo -e "${YELLOW}⚠${NC} No Kagent claim files found"
    else
        for KAGENT_FILE in $KAGENT_FILES; do
            echo -e "${BLUE}Processing: $(basename "$KAGENT_FILE")${NC}"
            
            # Reduce Kagent size for preview
            if grep -q "size: medium" "$KAGENT_FILE" 2>/dev/null; then
                sed -i.bak 's/size: medium/size: micro/g' "$KAGENT_FILE"
                rm -f "$KAGENT_FILE.bak"
                echo -e "  ${GREEN}✓${NC} Kagent: medium → micro (25m-100m CPU, 64Mi-256Mi RAM)"
            fi
            
            if grep -q "size: large" "$KAGENT_FILE" 2>/dev/null; then
                sed -i.bak 's/size: large/size: micro/g' "$KAGENT_FILE"
                rm -f "$KAGENT_FILE.bak"
                echo -e "  ${GREEN}✓${NC} Kagent: large → micro (25m-100m CPU, 64Mi-256Mi RAM)"
            fi
            
            # Disable Kagent replicas for preview (not needed for testing)
            if grep -q "replicas: [1-9]" "$KAGENT_FILE" 2>/dev/null; then
                sed -i.bak 's/replicas: [1-9]/replicas: 0/g' "$KAGENT_FILE"
                rm -f "$KAGENT_FILE.bak"
                echo -e "  ${GREEN}✓${NC} Kagent: disabled for preview (0 replicas)"
            fi
            
            # Also handle enabled: true -> enabled: false
            if grep -q "enabled: true" "$KAGENT_FILE" 2>/dev/null; then
                sed -i.bak 's/enabled: true/enabled: false/g' "$KAGENT_FILE"
                rm -f "$KAGENT_FILE.bak"
                echo -e "  ${GREEN}✓${NC} Kagent: disabled for preview"
            fi
        done
        
        echo -e "${GREEN}✓ Kagent optimization complete${NC}"
        echo -e "${BLUE}  Kagent disabled for preview (saves ~200m CPU, ~512Mi memory)${NC}"
    fi
else
    echo -e "${YELLOW}⊘${NC} Not in preview mode, skipping Kagent optimization"
fi

exit 0