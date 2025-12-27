#!/bin/bash
set -euo pipefail

# build-and-push.sh - Build and push container artifacts
# Builds container images and pushes to registry for deployment
# Outputs image_tag for use by downstream GitHub Actions jobs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common utilities
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

# Default values
SERVICE_NAME="${SERVICE_NAME:-}"
REGISTRY="${REGISTRY:-ghcr.io}"
REGISTRY_ORG="${REGISTRY_ORG:-arun4infra}"

# Usage information
usage() {
    cat << EOF
Usage: $0

Build and push container artifacts for deployment.
Uses environment variables for configuration.

Environment Variables:
  SERVICE_NAME          Service name (required, from GitHub repo name)
  GITHUB_SHA           Git commit SHA (required, from GitHub Actions)
  GITHUB_REF_NAME      Branch name (required, from GitHub Actions)
  REGISTRY_PASSWORD    Registry password (required, from secrets)
  REGISTRY             Container registry (default: ghcr.io)
  REGISTRY_ORG         Registry organization (default: arun4infra)

Outputs:
  Sets GITHUB_OUTPUT with image_tag for downstream jobs

Examples:
  # In GitHub Actions
  SERVICE_NAME=deepagents-runtime ./build-and-push.sh

EOF
}

# Validate environment
validate_environment() {
    log_info "Validating build environment"
    
    # Check required environment variables
    local required_vars=("SERVICE_NAME" "GITHUB_SHA" "GITHUB_REF_NAME" "REGISTRY_PASSWORD")
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required environment variable not set: $var"
            exit 1
        fi
    done
    
    # Check Docker availability
    if ! command -v docker &> /dev/null; then
        log_error "Docker is required but not installed"
        exit 1
    fi
    
    log_info "Environment validation completed successfully"
}

# Authenticate with container registry
authenticate_registry() {
    log_info "Authenticating with container registry: $REGISTRY"
    
    if echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY" -u "$GITHUB_ACTOR" --password-stdin; then
        log_success "Successfully authenticated with $REGISTRY"
    else
        log_error "Failed to authenticate with container registry"
        exit 1
    fi
}

# Build container image
build_image() {
    log_info "Building container image for service: $SERVICE_NAME"
    
    # Generate image tags
    local short_sha="${GITHUB_SHA:0:7}"
    local image_base="${REGISTRY}/${REGISTRY_ORG}/${SERVICE_NAME}"
    local image_tag_sha="${image_base}:${GITHUB_REF_NAME}-${short_sha}"
    local image_tag_latest="${image_base}:latest"
    
    log_info "Image tags:"
    log_info "  SHA tag: $image_tag_sha"
    log_info "  Latest tag: $image_tag_latest"
    
    # Build image with both tags
    if docker build -t "$image_tag_sha" -t "$image_tag_latest" .; then
        log_success "Container image built successfully"
    else
        log_error "Failed to build container image"
        exit 1
    fi
    
    # Export for push step
    export IMAGE_TAG_SHA="$image_tag_sha"
    export IMAGE_TAG_LATEST="$image_tag_latest"
}

# Push container image to registry
push_image() {
    log_info "Pushing container image to registry"
    
    # Push SHA-tagged image
    if docker push "$IMAGE_TAG_SHA"; then
        log_success "SHA-tagged image pushed: $IMAGE_TAG_SHA"
    else
        log_error "Failed to push SHA-tagged image"
        exit 1
    fi
    
    # Push latest tag (for main branch)
    if [[ "$GITHUB_REF_NAME" == "main" ]]; then
        if docker push "$IMAGE_TAG_LATEST"; then
            log_success "Latest image pushed: $IMAGE_TAG_LATEST"
        else
            log_error "Failed to push latest image"
            exit 1
        fi
    else
        log_info "Skipping latest tag push (not main branch)"
    fi
}

# Set GitHub Actions output
set_github_output() {
    log_info "Setting GitHub Actions output"
    
    # Primary image tag for deployment
    local output_tag="$IMAGE_TAG_SHA"
    
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "image_tag=$output_tag" >> "$GITHUB_OUTPUT"
        log_success "GitHub output set: image_tag=$output_tag"
    else
        log_warn "GITHUB_OUTPUT not set (not running in GitHub Actions)"
        echo "IMAGE_TAG=$output_tag"
    fi
    
    # Export for local use
    export BUILT_IMAGE_TAG="$output_tag"
}

# Main build and push execution
main() {
    local start_time
    start_time=$(date +%s)
    
    log_phase "BUILD AND PUSH PHASE"
    log_info "Starting build and push for service: $SERVICE_NAME"
    
    # Initialize logging
    init_logging "$SERVICE_NAME" "build-push"
    
    # Log environment information
    log_environment
    
    # Step 1: Validate environment
    validate_environment
    
    # Step 2: Authenticate with registry
    authenticate_registry
    
    # Step 3: Build container image
    build_image
    
    # Step 4: Push to registry
    push_image
    
    # Step 5: Set GitHub Actions output
    set_github_output
    
    local end_time
    local duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    log_success "Build and push completed successfully"
    log_info "Service: $SERVICE_NAME"
    log_info "Image: $BUILT_IMAGE_TAG"
    log_info "Duration: ${duration}s"
}

# Check for help flag
if [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

# Run main function
main