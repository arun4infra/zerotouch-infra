#!/bin/bash
set -euo pipefail

# post-build.sh - Post-build artifact handling helper
# Extracts artifact information and prepares for release pipeline

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Source common utilities
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/config-discovery.sh"
source "${SCRIPT_DIR}/../lib/logging.sh"

# Default values
TENANT=""
TRIGGER=""

# Usage information
usage() {
    cat << EOF
Usage: $0 --tenant=<name> --trigger=<pr|main>

Post-build artifact handling helper.
Extracts artifact information from build and prepares for release pipeline.

Arguments:
  --tenant=<name>     Tenant service name (required)
  --trigger=<pr|main> Workflow trigger type (required)

Environment Variables (set by build process):
  BUILT_IMAGE_NAME    Built image name (optional - will be calculated if not set)
  BUILT_IMAGE_TAG     Built image tag (optional - will be calculated if not set)
  BUILT_IMAGE_LATEST  Built latest tag (optional - for main branch only)

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --tenant=*)
                TENANT="${1#*=}"
                shift
                ;;
            --trigger=*)
                TRIGGER="${1#*=}"
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$TENANT" ]]; then
        log_error "Tenant name is required (--tenant=<name>)"
        usage
        exit 1
    fi

    if [[ -z "$TRIGGER" ]]; then
        log_error "Trigger type is required (--trigger=<pr|main>)"
        usage
        exit 1
    fi
}

# Extract artifact information from build
extract_artifact_info() {
    log_step_start "Extracting artifact information"
    
    local registry
    registry=$(get_tenant_release_config registry)
    
    # Extract artifact information from the CI execution
    # The build-service.sh script sets these based on the mode
    case "$TRIGGER" in
        "pr")
            local branch_name="${GITHUB_HEAD_REF:-feature/test-branch}"
            local commit_sha="${GITHUB_SHA:0:8}"
            
            # Use provided values or calculate defaults
            export BUILT_IMAGE_NAME="${BUILT_IMAGE_NAME:-${registry}/${TENANT}:${branch_name}-${commit_sha}}"
            export BUILT_IMAGE_TAG="${BUILT_IMAGE_TAG:-${branch_name}-${commit_sha}}"
            
            log_info "PR artifact information:"
            log_info "  Image: $BUILT_IMAGE_NAME"
            log_info "  Tag: $BUILT_IMAGE_TAG"
            log_info "  Branch: $branch_name"
            log_info "  Commit: $commit_sha"
            ;;
        "main")
            local commit_sha="${GITHUB_SHA:0:8}"
            
            # Use provided values or calculate defaults
            export BUILT_IMAGE_NAME="${BUILT_IMAGE_NAME:-${registry}/${TENANT}:main-${commit_sha}}"
            export BUILT_IMAGE_TAG="${BUILT_IMAGE_TAG:-main-${commit_sha}}"
            export BUILT_IMAGE_LATEST="${BUILT_IMAGE_LATEST:-${registry}/${TENANT}:latest}"
            
            log_info "Main branch artifact information:"
            log_info "  Image: $BUILT_IMAGE_NAME"
            log_info "  Tag: $BUILT_IMAGE_TAG"
            log_info "  Latest: $BUILT_IMAGE_LATEST"
            log_info "  Commit: $commit_sha"
            ;;
    esac
    
    log_artifact_info "$TENANT" "$registry" "$BUILT_IMAGE_TAG"
    log_step_end "Extracting artifact information" "SUCCESS"
    return 0
}

# Prepare release pipeline variables
prepare_release_variables() {
    log_step_start "Preparing release pipeline variables"
    
    # Set artifact information for release pipeline (main branch only)
    if [[ "$TRIGGER" == "main" ]]; then
        export ARTIFACT_ID="$BUILT_IMAGE_NAME"
        export ARTIFACT_TAG="$BUILT_IMAGE_TAG"
        export ARTIFACT_LATEST="$BUILT_IMAGE_LATEST"
        export ARTIFACT_REGISTRY=$(get_tenant_release_config registry)
        export ARTIFACT_SHA="${GITHUB_SHA}"
        
        log_info "Release pipeline variables prepared:"
        log_info "  ARTIFACT_ID: $ARTIFACT_ID"
        log_info "  ARTIFACT_TAG: $ARTIFACT_TAG"
        log_info "  ARTIFACT_LATEST: $ARTIFACT_LATEST"
        log_info "  ARTIFACT_REGISTRY: $ARTIFACT_REGISTRY"
        log_info "  ARTIFACT_SHA: ${ARTIFACT_SHA:0:8}"
    else
        log_info "PR workflow - no release pipeline variables needed"
    fi
    
    log_step_end "Preparing release pipeline variables" "SUCCESS"
    return 0
}

# Create artifact metadata
create_artifact_metadata() {
    log_step_start "Creating artifact metadata"
    
    local metadata_file
    local release_artifacts_dir
    
    # Use .release-artifacts directory in platform root for artifact metadata
    release_artifacts_dir="${PLATFORM_ROOT}/.release-artifacts"
    
    # Ensure .release-artifacts directory exists
    if [[ ! -d "$release_artifacts_dir" ]]; then
        mkdir -p "$release_artifacts_dir"
        log_info "Created .release-artifacts directory: $release_artifacts_dir"
    fi
    
    # Generate unique metadata filename with timestamp and tenant
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    metadata_file="${release_artifacts_dir}/${TENANT}-${TRIGGER}-${timestamp}.artifact-metadata.json"
    
    # Create comprehensive metadata JSON
    cat > "$metadata_file" << EOF
{
  "tenant": "$TENANT",
  "trigger": "$TRIGGER",
  "built_image_name": "$BUILT_IMAGE_NAME",
  "built_image_tag": "$BUILT_IMAGE_TAG",
  "built_image_latest": "${BUILT_IMAGE_LATEST:-}",
  "registry": "$(get_tenant_release_config registry)",
  "artifact_type": "$(get_artifact_type "$TRIGGER")",
  "immutable": $(get_artifact_immutable_flag "$TRIGGER"),
  "deployable": $(get_artifact_deployable_flag "$TRIGGER"),
  "created_at": "$(get_timestamp)",
  "created_by": "${GITHUB_ACTOR:-$(whoami)}",
  "source_commit": "${GITHUB_SHA}",
  "source_commit_short": "${GITHUB_SHA:0:8}",
  "source_branch": "${GITHUB_REF_NAME:-${GITHUB_HEAD_REF:-unknown}}",
  "workflow_run_id": "${GITHUB_RUN_ID:-unknown}",
  "workflow_run_url": "${GITHUB_SERVER_URL:-}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}",
  "build_environment": "github-runners-kind",
  "validation_mode": "preview"
}
EOF
    
    log_info "Artifact metadata created: $metadata_file"
    log_debug "Metadata content:"
    if [[ $(get_log_level_num) -ge $LOG_LEVEL_DEBUG ]]; then
        cat "$metadata_file"
    fi
    
    export ARTIFACT_METADATA_FILE="$metadata_file"
    
    log_step_end "Creating artifact metadata" "SUCCESS"
    return 0
}

# Get artifact type based on trigger
get_artifact_type() {
    local trigger="$1"
    case "$trigger" in
        "pr")
            echo "preview"
            ;;
        "main")
            echo "release"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Get artifact immutable flag based on trigger
get_artifact_immutable_flag() {
    local trigger="$1"
    case "$trigger" in
        "pr")
            echo "false"
            ;;
        "main")
            echo "true"
            ;;
        *)
            echo "false"
            ;;
    esac
}

# Get artifact deployable flag based on trigger
get_artifact_deployable_flag() {
    local trigger="$1"
    case "$trigger" in
        "pr")
            echo "false"
            ;;
        "main")
            echo "true"
            ;;
        *)
            echo "false"
            ;;
    esac
}

# Main post-build execution
main() {
    log_info "Starting post-build processing for tenant: $TENANT, trigger: $TRIGGER"
    
    # Extract artifact information
    if ! extract_artifact_info; then
        log_error "Failed to extract artifact information"
        exit 1
    fi
    
    # Run artifact management (handles immutable artifacts for main branch)
    log_info "Running artifact management..."
    if ! "${SCRIPT_DIR}/artifact-manager.sh" --tenant="$TENANT" --trigger="$TRIGGER"; then
        log_error "Artifact management failed"
        exit 1
    fi
    
    # Prepare release pipeline variables
    if ! prepare_release_variables; then
        log_error "Failed to prepare release variables"
        exit 1
    fi
    
    # Create artifact metadata
    if ! create_artifact_metadata; then
        log_error "Failed to create artifact metadata"
        exit 1
    fi
    
    log_success "Post-build processing completed successfully"
    
    # Export results for use by calling script
    export POST_BUILD_STATUS="SUCCESS"
    export POST_BUILD_TENANT="$TENANT"
    export POST_BUILD_TRIGGER="$TRIGGER"
    
    # Export artifact manager results if available
    if [[ -n "${RELEASE_ARTIFACT_ID:-}" ]]; then
        export ARTIFACT_ID="$RELEASE_ARTIFACT_ID"
        export ARTIFACT_TAG="$RELEASE_ARTIFACT_TAG"
        export ARTIFACT_LATEST="$RELEASE_ARTIFACT_LATEST"
        
        log_info "Artifact information exported for release pipeline:"
        log_info "  ARTIFACT_ID: $ARTIFACT_ID"
        log_info "  ARTIFACT_TAG: $ARTIFACT_TAG"
        log_info "  ARTIFACT_LATEST: $ARTIFACT_LATEST"
    fi
}

# Parse arguments and run main function
parse_args "$@"
main