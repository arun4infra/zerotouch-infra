#!/bin/bash
# Exclude local-path-provisioner from platform-bootstrap for Kind/preview
# Kind comes with its own local-path-provisioner, so we don't need to deploy ours
#
# Usage: ./04-disable-local-path-provisioner.sh [--force]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

FORCE_UPDATE=false
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
    echo -e "${BLUE}Excluding local-path-provisioner from platform-bootstrap for preview mode...${NC}"
    
    PLATFORM_BOOTSTRAP="$REPO_ROOT/bootstrap/10-platform-bootstrap.yaml"
    
    if [ -f "$PLATFORM_BOOTSTRAP" ]; then
        # Check current exclude pattern
        CURRENT_EXCLUDE=$(grep "exclude:" "$PLATFORM_BOOTSTRAP" 2>/dev/null || echo "")
        
        if echo "$CURRENT_EXCLUDE" | grep -q "01-local-path-provisioner.yaml"; then
            echo -e "  ${GREEN}✓${NC} local-path-provisioner already excluded"
        else
            # Update exclude pattern to include local-path-provisioner
            if grep -q "exclude: '01-eso.yaml'" "$PLATFORM_BOOTSTRAP" 2>/dev/null; then
                # Change: exclude: '01-eso.yaml'
                # To:     exclude: '{01-eso.yaml,01-local-path-provisioner.yaml}'
                sed -i.bak "s|exclude: '01-eso.yaml'|exclude: '{01-eso.yaml,01-local-path-provisioner.yaml}'|g" "$PLATFORM_BOOTSTRAP"
                rm -f "$PLATFORM_BOOTSTRAP.bak"
                echo -e "  ${GREEN}✓${NC} Added local-path-provisioner to exclude pattern"
            elif grep -q 'exclude:.*{' "$PLATFORM_BOOTSTRAP" 2>/dev/null; then
                # Already has a glob pattern, add local-path-provisioner to it
                sed -i.bak "s|exclude: '{\([^}]*\)}'|exclude: '{\1,01-local-path-provisioner.yaml}'|g" "$PLATFORM_BOOTSTRAP"
                rm -f "$PLATFORM_BOOTSTRAP.bak"
                echo -e "  ${GREEN}✓${NC} Added local-path-provisioner to existing exclude pattern"
            else
                echo -e "  ${YELLOW}⚠${NC} No exclude pattern found - manual intervention needed"
            fi
        fi
        
        # Verify
        echo -e "${BLUE}Verifying exclude pattern:${NC}"
        grep -n "exclude:" "$PLATFORM_BOOTSTRAP" || echo "  (no exclude found)"
    else
        echo -e "  ${YELLOW}⚠${NC} platform-bootstrap.yaml not found"
    fi
    
    # Also disable the Application file itself
    LOCAL_PATH_APP="$REPO_ROOT/bootstrap/components/01-local-path-provisioner.yaml"
    if [ -f "$LOCAL_PATH_APP" ]; then
        mv "$LOCAL_PATH_APP" "$LOCAL_PATH_APP.disabled"
        echo -e "  ${GREEN}✓${NC} Disabled 01-local-path-provisioner.yaml Application"
    elif [ -f "$LOCAL_PATH_APP.disabled" ]; then
        echo -e "  ${GREEN}✓${NC} 01-local-path-provisioner.yaml already disabled"
    fi
    
    echo -e "${GREEN}✓ local-path-provisioner exclusion applied${NC}"
    echo -e "  ${BLUE}ℹ${NC} Kind's built-in provisioner will be used instead"
fi
