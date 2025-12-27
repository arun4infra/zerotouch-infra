#!/bin/bash
set -euo pipefail

# ==============================================================================
# Shared Script: Load Docker Image into Kind Cluster
# ==============================================================================
# Purpose: Load Docker image into Kind cluster
# Usage: ./load-image-to-kind.sh --service=<service-name> [--image-tag=<tag>]
# ==============================================================================

# Default values
SERVICE_NAME=""
IMAGE_TAG="ci-test"
CLUSTER_NAME="zerotouch-preview"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[LOAD]${NC} $*"; }
log_success() { echo -e "${GREEN}[LOAD]${NC} $*"; }
log_error() { echo -e "${RED}[LOAD]${NC} $*"; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --service=*)
            SERVICE_NAME="${1#*=}"
            shift
            ;;
        --image-tag=*)
            IMAGE_TAG="${1#*=}"
            shift
            ;;
        *)
            log_error "Unknown argument: $1"
            echo "Usage: $0 --service=<service-name> [--image-tag=<tag>]"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$SERVICE_NAME" ]]; then
    log_error "Service name is required. Use --service=<service-name>"
    exit 1
fi

echo "================================================================================"
echo "Loading Docker Image into Kind Cluster"
echo "================================================================================"
echo "  Service:   ${SERVICE_NAME}"
echo "  Image Tag: ${IMAGE_TAG}"
echo "  Cluster:   ${CLUSTER_NAME}"
echo "================================================================================"

# Determine if this is a registry image (contains registry URL) or local image
if [[ "$IMAGE_TAG" == *"ghcr.io"* || "$IMAGE_TAG" == *":"* ]]; then
    # This is a full registry image tag (e.g., ghcr.io/arun4infra/service:sha-123)
    FULL_IMAGE_NAME="$IMAGE_TAG"
    log_info "Loading registry image: $FULL_IMAGE_NAME"
else
    # This is a local image tag (e.g., ci-test)
    FULL_IMAGE_NAME="${SERVICE_NAME}:${IMAGE_TAG}"
    log_info "Loading local image: $FULL_IMAGE_NAME"
fi

log_info "Loading image into Kind cluster..."
if ! kind load docker-image "$FULL_IMAGE_NAME" --name "${CLUSTER_NAME}"; then
    log_error "Failed to load image into Kind cluster"
    exit 1
fi

log_success "Image loaded successfully into Kind cluster: $FULL_IMAGE_NAME"