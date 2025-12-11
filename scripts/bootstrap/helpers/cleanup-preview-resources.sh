#!/bin/bash
# Cleanup Preview Resources
# Removes tenant-specific resources that aren't needed in preview environments
#
# Usage: ./cleanup-preview-resources.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Cleanup Preview Resources                                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Delete tenant repository ExternalSecrets (they require SSM params we don't have in preview)
echo -e "${BLUE}Removing tenant repository ExternalSecrets...${NC}"

# Wait for ArgoCD to create ExternalSecrets and monitor for new ones
MAX_WAIT=60
ELAPSED=0
LAST_COUNT=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    # Get all tenant repo ExternalSecrets
    TENANT_REPOS=$(kubectl get externalsecrets -A -o json 2>/dev/null | jq -r '.items[] | select(.metadata.name | startswith("repo-")) | "\(.metadata.namespace)/\(.metadata.name)"')
    CURRENT_COUNT=$(echo "$TENANT_REPOS" | grep -c . || echo "0")
    
    # If count changed, reset timer to give ArgoCD time to create more
    if [ "$CURRENT_COUNT" -ne "$LAST_COUNT" ]; then
        echo -e "${BLUE}  Found $CURRENT_COUNT tenant repo ExternalSecrets, waiting for more...${NC}"
        LAST_COUNT=$CURRENT_COUNT
        ELAPSED=0
    fi
    
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    
    # If we've seen the same count for 30 seconds, assume we're done
    if [ $ELAPSED -ge 30 ] && [ "$CURRENT_COUNT" -gt 0 ]; then
        break
    fi
done

# Delete all tenant repo ExternalSecrets
if [ -n "$TENANT_REPOS" ]; then
    echo ""
    echo "$TENANT_REPOS" | while read -r resource; do
        namespace=$(echo "$resource" | cut -d'/' -f1)
        name=$(echo "$resource" | cut -d'/' -f2)
        
        echo -e "  ${YELLOW}✗${NC} Deleting: $namespace/$name"
        kubectl delete externalsecret "$name" -n "$namespace" --ignore-not-found=true
    done
else
    echo -e "${GREEN}✓ No tenant repository ExternalSecrets found${NC}"
fi

echo ""
echo -e "${GREEN}✓ Preview resource cleanup complete${NC}"
echo ""

exit 0
