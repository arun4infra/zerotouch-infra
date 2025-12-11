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

# Wait for ArgoCD to create the ExternalSecrets first
sleep 10

# Delete tenant repo ExternalSecrets
TENANT_REPOS=$(kubectl get externalsecrets -A -o json | jq -r '.items[] | select(.metadata.name | startswith("repo-")) | "\(.metadata.namespace)/\(.metadata.name)"')

if [ -n "$TENANT_REPOS" ]; then
    echo "$TENANT_REPOS" | while read -r resource; do
        namespace=$(echo "$resource" | cut -d'/' -f1)
        name=$(echo "$resource" | cut -d'/' -f2)
        
        # Skip the zerotouch-tenants repo (we have SSM params for it)
        if [ "$name" = "repo-zerotouch-tenants" ]; then
            echo -e "  ${BLUE}ℹ${NC}  Keeping: $namespace/$name (has SSM parameters)"
            continue
        fi
        
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
