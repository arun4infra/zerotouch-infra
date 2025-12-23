#!/bin/bash
# Optimize NATS resources for preview mode
# Disables persistence and reduces CPU/memory usage

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
    echo -e "${BLUE}Optimizing NATS resources for preview mode...${NC}"
    
    NATS_FILE="$REPO_ROOT/bootstrap/argocd/base/01-nats.yaml"
    
    if [ -f "$NATS_FILE" ]; then
        # Disable JetStream file store (uses PVCs)
        if grep -q "enabled: true" "$NATS_FILE" 2>/dev/null; then
            # Disable fileStore PVC - use awk for better cross-platform compatibility
            awk '
                /fileStore:/ { in_filestore = 1 }
                /pvc:/ && in_filestore { in_pvc = 1 }
                /enabled: true/ && in_filestore && in_pvc { gsub(/enabled: true/, "enabled: false") }
                /^[[:space:]]*[^[:space:]]/ && !/^[[:space:]]*#/ && !/fileStore:/ && !/pvc:/ && in_filestore { in_filestore = 0; in_pvc = 0 }
                { print }
            ' "$NATS_FILE" > "$NATS_FILE.tmp" && mv "$NATS_FILE.tmp" "$NATS_FILE"
            
            # Keep memoryStore enabled for in-memory streams
            awk '
                /memoryStore:/ { in_memstore = 1 }
                /maxSize:/ && in_memstore { in_maxsize = 1 }
                /enabled: false/ && in_memstore { gsub(/enabled: false/, "enabled: true") }
                /^[[:space:]]*[^[:space:]]/ && !/^[[:space:]]*#/ && !/memoryStore:/ && !/maxSize:/ && in_memstore { in_memstore = 0; in_maxsize = 0 }
                { print }
            ' "$NATS_FILE" > "$NATS_FILE.tmp" && mv "$NATS_FILE.tmp" "$NATS_FILE"
            
            echo -e "  ${GREEN}✓${NC} Disabled NATS persistence (using memory-only mode)"
        fi
        
        # Reduce NATS resources
        if grep -q "cpu: 100m" "$NATS_FILE" 2>/dev/null; then
            sed -i.bak 's/cpu: 100m/cpu: 50m/g' "$NATS_FILE"
            sed -i.bak 's/cpu: 500m/cpu: 250m/g' "$NATS_FILE"
            rm -f "$NATS_FILE.bak"
            echo -e "  ${GREEN}✓${NC} Reduced NATS CPU (50m request, 250m limit)"
        fi
        
        echo -e "${GREEN}✓ NATS optimization complete${NC}"
    else
        echo -e "${YELLOW}⚠${NC} NATS file not found: $NATS_FILE"
    fi
else
    echo -e "${YELLOW}⊘${NC} Not in preview mode, skipping NATS optimization"
fi

exit 0