#!/bin/bash
# Tier 3 Script: Setup Preview Cluster
# Creates Kind cluster and installs required tools for CI/CD testing
#
# Environment Variables (required):
#   AWS_ACCESS_KEY_ID - AWS access key for ESO
#   AWS_SECRET_ACCESS_KEY - AWS secret key for ESO
#   AWS_SESSION_TOKEN - AWS session token (optional, for OIDC)
#
# Exit Codes:
#   0 - Success
#   1 - Missing AWS credentials
#   2 - Tool installation failed
#   3 - Kind cluster creation failed

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="zerotouch-preview"
KIND_CONFIG="$SCRIPT_DIR/kind-config.yaml"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Setup Preview Cluster                                     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Validate AWS credentials
if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    echo -e "${RED}Error: AWS credentials required${NC}"
    echo -e "Set: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN (optional)"
    exit 1
fi

echo -e "${GREEN}✓ AWS credentials configured${NC}"
echo ""

# Install required tools
echo -e "${YELLOW}Checking required tools...${NC}"

# kubectl
if ! command -v kubectl &> /dev/null; then
    echo -e "${BLUE}Installing kubectl...${NC}"
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/kubectl || exit 2
fi
echo -e "${GREEN}✓ kubectl available${NC}"

# helm
if ! command -v helm &> /dev/null; then
    echo -e "${BLUE}Installing helm...${NC}"
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash || exit 2
fi
echo -e "${GREEN}✓ helm available${NC}"

# kind
if ! command -v kind &> /dev/null; then
    echo -e "${BLUE}Installing kind...${NC}"
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind || exit 2
fi
echo -e "${GREEN}✓ kind available${NC}"

echo ""

# Create Kind cluster
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo -e "${YELLOW}Kind cluster '$CLUSTER_NAME' already exists${NC}"
else
    echo -e "${BLUE}Creating Kind cluster '$CLUSTER_NAME'...${NC}"
    if [ ! -f "$KIND_CONFIG" ]; then
        echo -e "${RED}Error: Kind config not found at $KIND_CONFIG${NC}"
        exit 3
    fi
    kind create cluster --config "$KIND_CONFIG" || exit 3
    echo -e "${GREEN}✓ Kind cluster created${NC}"
fi

# Set kubectl context
kubectl config use-context "kind-${CLUSTER_NAME}"

# Label nodes for database workloads
echo -e "${BLUE}Labeling nodes for database workloads...${NC}"
kubectl label nodes --all workload.bizmatters.dev/databases=true --overwrite
echo -e "${GREEN}✓ Nodes labeled${NC}"

echo ""

# Exclude tenant components in preview mode
# Tenants require SSM credentials that services don't have
echo -e "${BLUE}Excluding tenant components for preview mode...${NC}"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Change root.yaml to exclude 11-platform-tenants.yaml
if [ -f "$REPO_ROOT/bootstrap/root.yaml" ]; then
    sed -i.bak "s|include: '{00-\*,10-\*,11-\*}.yaml'|include: '{00-*,10-*}.yaml'|" "$REPO_ROOT/bootstrap/root.yaml"
    rm -f "$REPO_ROOT/bootstrap/root.yaml.bak"
    echo -e "${GREEN}✓ Tenant components excluded from bootstrap${NC}"
fi

echo ""
echo -e "${GREEN}✓ Preview cluster setup complete${NC}"
echo -e "  Cluster: ${BLUE}kind-${CLUSTER_NAME}${NC}"
echo -e "  Context: ${BLUE}kind-${CLUSTER_NAME}${NC}"
echo ""

exit 0
