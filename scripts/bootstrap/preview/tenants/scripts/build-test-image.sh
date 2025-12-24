#!/bin/bash
set -euo pipefail

# ==============================================================================
# Shared Script: Build Test Image
# ==============================================================================
# Purpose: Build Docker test image and load into Kind cluster
# Usage: ./build-test-image.sh --service=<service-name> [--image-tag=<tag>]
# Moved from: ide-orchestrator/scripts/ci/build.sh (test mode only)
# ==============================================================================

# Default values
SERVICE_NAME=""
IMAGE_TAG="ci-test"
CLUSTER_NAME="zerotouch-preview"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[BUILD]${NC} $*"; }
log_success() { echo -e "${GREEN}[BUILD]${NC} $*"; }
log_error() { echo -e "${RED}[BUILD]${NC} $*"; }

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
echo "Building Test Image"
echo "================================================================================"
echo "  Service:   ${SERVICE_NAME}"
echo "  Image Tag: ${IMAGE_TAG}"
echo "  Cluster:   ${CLUSTER_NAME}"
echo "================================================================================"

# Use the centralized build script in test mode
export SERVICE_NAME="${SERVICE_NAME}"
"${SCRIPT_DIR}/build.sh" --mode=test

log_success "Build and load complete: ${SERVICE_NAME}:${IMAGE_TAG}"