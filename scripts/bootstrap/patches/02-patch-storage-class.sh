#!/bin/bash
# Patch storage class from local-path to standard for Kind
# Usage: ./02-patch-storage-class.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Patching storage class to 'standard'...${NC}"

# Patch compositions
for file in "$REPO_ROOT"/platform/05-databases/compositions/*.yaml; do
    if [ -f "$file" ]; then
        if grep -q "local-path" "$file" 2>/dev/null; then
            sed -i.bak \
                -e 's/storageClass: local-path/storageClass: standard/g' \
                -e 's/storageClassName: local-path/storageClassName: standard/g' \
                "$file"
            rm -f "$file.bak"
            echo -e "  ${GREEN}✓${NC} Patched: $(basename "$file")"
        fi
    fi
done

echo -e "${GREEN}✓ Storage class patches applied${NC}"
