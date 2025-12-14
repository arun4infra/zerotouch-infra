#!/bin/bash
# Apply all preview/Kind patches to the platform
# This script runs all numbered patch scripts in order
#
# Usage: ./00-apply-all-patches.sh
#
# Run this BEFORE ArgoCD syncs from file:///repo

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Applying Preview/Kind Patches                             ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Run all numbered patch scripts (01-*, 02-*, etc.)
for script in "$SCRIPT_DIR"/[0-9][0-9]-*.sh; do
    if [ -f "$script" ] && [ "$script" != "$0" ]; then
        script_name=$(basename "$script")
        echo -e "${BLUE}Running: $script_name${NC}"
        chmod +x "$script"
        "$script"
        echo ""
    fi
done

echo -e "${GREEN}✓ All preview patches applied successfully${NC}"
