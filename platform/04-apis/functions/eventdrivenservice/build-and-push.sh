#!/bin/bash
# Build and push EventDrivenService composition function to GHCR
# This script fetches credentials from AWS SSM Parameter Store and pushes the function image

set -e

# Get script directory and change to it
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
IMAGE_NAME="ghcr.io/arun4infra/function-eventdrivenservice"
VERSION="${VERSION:-v0.1.0}"
IMAGE="${IMAGE_NAME}:${VERSION}"
AWS_REGION="${AWS_REGION:-ap-south-1}"

# SSM Parameter paths (matching existing pattern)
SSM_USERNAME_KEY="/zerotouch/prod/platform/ghcr/username"
SSM_PASSWORD_KEY="/zerotouch/prod/platform/ghcr/password"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   EventDrivenService Function - Build & Push                ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Working directory: $SCRIPT_DIR${NC}"
echo ""

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"

if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker installed${NC}"

if ! command -v aws &> /dev/null; then
    echo -e "${RED}✗ AWS CLI not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ AWS CLI installed${NC}"

if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}✗ AWS credentials not configured${NC}"
    echo -e "${YELLOW}Configure AWS credentials:${NC}"
    echo -e "  ${GREEN}aws configure${NC}"
    exit 1
fi
echo -e "${GREEN}✓ AWS credentials configured${NC}"
echo ""

# Fetch GHCR credentials from AWS SSM
echo -e "${BLUE}Fetching GHCR credentials from AWS SSM...${NC}"

GHCR_USERNAME=$(aws ssm get-parameter \
    --name "$SSM_USERNAME_KEY" \
    --region "$AWS_REGION" \
    --query 'Parameter.Value' \
    --output text 2>/dev/null)

if [ -z "$GHCR_USERNAME" ]; then
    echo -e "${RED}✗ Failed to fetch GHCR username from SSM${NC}"
    echo -e "${YELLOW}Parameter: $SSM_USERNAME_KEY${NC}"
    echo -e "${YELLOW}Ensure the parameter exists in AWS SSM Parameter Store${NC}"
    echo ""
    echo -e "${YELLOW}To create the parameter:${NC}"
    echo -e "  ${GREEN}aws ssm put-parameter \\${NC}"
    echo -e "  ${GREEN}  --name '$SSM_USERNAME_KEY' \\${NC}"
    echo -e "  ${GREEN}  --value 'your-github-username' \\${NC}"
    echo -e "  ${GREEN}  --type SecureString \\${NC}"
    echo -e "  ${GREEN}  --region $AWS_REGION${NC}"
    exit 1
fi

GHCR_PASSWORD=$(aws ssm get-parameter \
    --name "$SSM_PASSWORD_KEY" \
    --with-decryption \
    --region "$AWS_REGION" \
    --query 'Parameter.Value' \
    --output text 2>/dev/null)

if [ -z "$GHCR_PASSWORD" ]; then
    echo -e "${RED}✗ Failed to fetch GHCR password from SSM${NC}"
    echo -e "${YELLOW}Parameter: $SSM_PASSWORD_KEY${NC}"
    echo -e "${YELLOW}Ensure the parameter exists in AWS SSM Parameter Store${NC}"
    echo ""
    echo -e "${YELLOW}To create the parameter:${NC}"
    echo -e "  ${GREEN}aws ssm put-parameter \\${NC}"
    echo -e "  ${GREEN}  --name '$SSM_PASSWORD_KEY' \\${NC}"
    echo -e "  ${GREEN}  --value 'your-github-token' \\${NC}"
    echo -e "  ${GREEN}  --type SecureString \\${NC}"
    echo -e "  ${GREEN}  --region $AWS_REGION${NC}"
    exit 1
fi

echo -e "${GREEN}✓ GHCR credentials fetched from SSM${NC}"
echo -e "${GREEN}✓ Username: $GHCR_USERNAME${NC}"
echo ""

# Build the Docker image
echo -e "${BLUE}Building Docker image...${NC}"
echo -e "${BLUE}Image: $IMAGE${NC}"
echo ""

if docker build -t "$IMAGE" .; then
    echo -e "${GREEN}✓ Docker image built successfully${NC}"
else
    echo -e "${RED}✗ Docker build failed${NC}"
    exit 1
fi
echo ""

# Login to GHCR
echo -e "${BLUE}Logging in to GHCR...${NC}"

if echo "$GHCR_PASSWORD" | docker login ghcr.io -u "$GHCR_USERNAME" --password-stdin > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Logged in to ghcr.io${NC}"
else
    echo -e "${RED}✗ Failed to login to GHCR${NC}"
    exit 1
fi
echo ""

# Push the image
echo -e "${BLUE}Pushing image to GHCR...${NC}"
echo -e "${BLUE}Image: $IMAGE${NC}"
echo ""

if docker push "$IMAGE"; then
    echo -e "${GREEN}✓ Image pushed successfully${NC}"
else
    echo -e "${RED}✗ Failed to push image${NC}"
    exit 1
fi
echo ""

# Tag as latest if this is a release version
if [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    LATEST_IMAGE="${IMAGE_NAME}:latest"
    echo -e "${BLUE}Tagging as latest...${NC}"
    docker tag "$IMAGE" "$LATEST_IMAGE"
    docker push "$LATEST_IMAGE"
    echo -e "${GREEN}✓ Tagged and pushed as latest${NC}"
    echo ""
fi

# Logout from GHCR (security best practice)
docker logout ghcr.io > /dev/null 2>&1

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Build & Push Complete                                     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ Function image available at: $IMAGE${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Install function in cluster:"
echo -e "     ${GREEN}make install${NC}"
echo ""
echo -e "  2. Verify function installation:"
echo -e "     ${GREEN}kubectl get functions${NC}"
echo -e "     ${GREEN}kubectl get pods -n crossplane-system | grep function-eventdrivenservice${NC}"
echo ""
echo -e "  3. Deploy composition:"
echo -e "     ${GREEN}kubectl apply -f ../../definitions/xeventdrivenservices.yaml${NC}"
echo -e "     ${GREEN}kubectl apply -f ../../compositions/event-driven-service-composition.yaml${NC}"
echo ""
echo -e "  4. Test with example claim:"
echo -e "     ${GREEN}kubectl apply -f ../../examples/minimal-claim.yaml${NC}"
echo ""
