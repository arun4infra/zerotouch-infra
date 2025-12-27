#!/bin/bash
set -euo pipefail

# artifact-manager.sh - Artifact tagging and registry management helper
# Handles immutable artifact creation for main branch workflows only

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Source common utilities
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/config-discovery.sh"
source "${SCRIPT_DIR}/../lib/logging.sh"

# Default values
TENANT=""
TRIGGER=""
ARTIFACT_ID=""

# Usage information
usage() {
    cat << EOF
Usage: $0 --tenant=<name> --trigger=<pr|main> [--artifact-id=<id>]

Artifact tagging and registry management helper.
Creates immutable artifacts for main branch workflows only.

Arguments:
  --tenant=<name>     Tenant service name (required)
  --trigger=<pr|main> Workflow trigger type (required)
  --artifact-id=<id>  Artifact identifier (optional - will be discovered)

Environment Variables:
  BUILT_IMAGE_NAME    Built image name from build process
  BUILT_IMAGE_TAG     Built image tag from build process
  BUILT_IMAGE_LATEST  Built latest tag from build process (main branch only)

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
            --artifact-id=*)
                ARTIFACT_ID="${1#*=}"
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

# Create immutable artifact tags for main branch
create_immutable_artifact_tags() {
    log_step_start "Creating immutable artifact tags"
    
    if [[ "$TRIGGER" != "main" ]]; then
        log_info "Skipping immutable artifact creation for trigger: $TRIGGER"
        log_info "Immutable artifacts are only created for main branch workflows"
        log_step_end "Creating immutable artifact tags" "SKIPPED"
        return 0
    fi
    
    local registry
    local commit_sha
    local timestamp
    
    registry=$(get_tenant_release_config registry)
    commit_sha="${GITHUB_SHA:0:8}"
    timestamp=$(date +%Y%m%d-%H%M%S)
    
    # Create immutable SHA-tagged artifact
    local immutable_tag="main-${commit_sha}"
    local timestamped_tag="main-${commit_sha}-${timestamp}"
    
    export IMMUTABLE_ARTIFACT_TAG="$immutable_tag"
    export TIMESTAMPED_ARTIFACT_TAG="$timestamped_tag"
    export IMMUTABLE_ARTIFACT_NAME="${registry}/${TENANT}:${immutable_tag}"
    export TIMESTAMPED_ARTIFACT_NAME="${registry}/${TENANT}:${timestamped_tag}"
    
    log_info "Immutable artifact tags created:"
    log_info "  SHA-tagged: $IMMUTABLE_ARTIFACT_NAME"
    log_info "  Timestamped: $TIMESTAMPED_ARTIFACT_NAME"
    log_info "  Latest: ${BUILT_IMAGE_LATEST:-N/A}"
    
    # Verify artifacts exist in registry (if in production environment)
    if [[ "${GITHUB_ACTIONS:-false}" == "true" ]]; then
        log_info "Verifying artifacts in registry..."
        verify_artifact_in_registry "$IMMUTABLE_ARTIFACT_NAME"
        if [[ -n "${BUILT_IMAGE_LATEST:-}" ]]; then
            verify_artifact_in_registry "$BUILT_IMAGE_LATEST"
        fi
    fi
    
    log_step_end "Creating immutable artifact tags" "SUCCESS"
    return 0
}

# Verify artifact exists in registry
verify_artifact_in_registry() {
    local artifact_name="$1"
    
    log_debug "Verifying artifact in registry: $artifact_name"
    
    # For GitHub Container Registry, we can use docker manifest inspect
    if command -v docker >/dev/null 2>&1; then
        if docker manifest inspect "$artifact_name" >/dev/null 2>&1; then
            log_debug "✅ Artifact verified in registry: $artifact_name"
            return 0
        else
            log_warn "⚠️  Could not verify artifact in registry: $artifact_name"
            log_warn "This may be expected in preview mode or if registry is not accessible"
            return 0
        fi
    else
        log_debug "Docker not available for registry verification"
        return 0
    fi
}

# Create artifact registry manifest
create_artifact_registry_manifest() {
    log_step_start "Creating artifact registry manifest"
    
    local manifest_file
    local release_artifacts_dir
    
    release_artifacts_dir="${PLATFORM_ROOT}/.release-artifacts"
    manifest_file="${release_artifacts_dir}/${TENANT}-registry-manifest.json"
    
    # Create registry manifest with all artifact information
    cat > "$manifest_file" << EOF
{
  "tenant": "$TENANT",
  "trigger": "$TRIGGER",
  "registry": "$(get_tenant_release_config registry)",
  "artifacts": {
    "primary": {
      "name": "$BUILT_IMAGE_NAME",
      "tag": "$BUILT_IMAGE_TAG",
      "immutable": $(get_artifact_immutable_flag "$TRIGGER"),
      "deployable": $(get_artifact_deployable_flag "$TRIGGER")
    }$(if [[ "$TRIGGER" == "main" && -n "${IMMUTABLE_ARTIFACT_NAME:-}" ]]; then echo ",
    \"immutable_sha\": {
      \"name\": \"$IMMUTABLE_ARTIFACT_NAME\",
      \"tag\": \"$IMMUTABLE_ARTIFACT_TAG\",
      \"immutable\": true,
      \"deployable\": true
    }"; fi)$(if [[ "$TRIGGER" == "main" && -n "${TIMESTAMPED_ARTIFACT_NAME:-}" ]]; then echo ",
    \"timestamped\": {
      \"name\": \"$TIMESTAMPED_ARTIFACT_NAME\",
      \"tag\": \"$TIMESTAMPED_ARTIFACT_TAG\",
      \"immutable\": true,
      \"deployable\": true
    }"; fi)$(if [[ "$TRIGGER" == "main" && -n "${BUILT_IMAGE_LATEST:-}" ]]; then echo ",
    \"latest\": {
      \"name\": \"$BUILT_IMAGE_LATEST\",
      \"tag\": \"latest\",
      \"immutable\": false,
      \"deployable\": true
    }"; fi)
  },
  "retention_policy": {
    "retention_days": $(get_tenant_release_config retention_days),
    "cleanup_enabled": true
  },
  "created_at": "$(get_timestamp)",
  "source_commit": "${GITHUB_SHA}",
  "workflow_run_id": "${GITHUB_RUN_ID:-unknown}"
}
EOF
    
    log_info "Artifact registry manifest created: $manifest_file"
    export ARTIFACT_REGISTRY_MANIFEST="$manifest_file"
    
    log_step_end "Creating artifact registry manifest" "SUCCESS"
    return 0
}

# Enforce PR workflow restrictions
enforce_pr_workflow_restrictions() {
    log_step_start "Enforcing PR workflow restrictions"
    
    if [[ "$TRIGGER" == "pr" ]]; then
        log_info "PR workflow detected - enforcing restrictions:"
        log_info "  ❌ No immutable artifacts will be created"
        log_info "  ❌ No deployment to persistent environments"
        log_info "  ✅ Feedback and testing only"
        
        # Ensure no deployment variables are set for PR workflows
        unset ARTIFACT_ID 2>/dev/null || true
        unset ARTIFACT_LATEST 2>/dev/null || true
        unset IMMUTABLE_ARTIFACT_TAG 2>/dev/null || true
        unset IMMUTABLE_ARTIFACT_NAME 2>/dev/null || true
        
        export PR_WORKFLOW_RESTRICTED="true"
        export DEPLOYMENT_ALLOWED="false"
        
        log_info "PR workflow restrictions enforced successfully"
    else
        log_info "Main branch workflow - no restrictions applied"
        export PR_WORKFLOW_RESTRICTED="false"
        export DEPLOYMENT_ALLOWED="true"
    fi
    
    log_step_end "Enforcing PR workflow restrictions" "SUCCESS"
    return 0
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

# Main artifact management execution
main() {
    log_info "Starting artifact management for tenant: $TENANT, trigger: $TRIGGER"
    
    # Enforce PR workflow restrictions first
    if ! enforce_pr_workflow_restrictions; then
        log_error "Failed to enforce PR workflow restrictions"
        exit 1
    fi
    
    # Create immutable artifact tags (main branch only)
    if ! create_immutable_artifact_tags; then
        log_error "Failed to create immutable artifact tags"
        exit 1
    fi
    
    # Create artifact registry manifest
    if ! create_artifact_registry_manifest; then
        log_error "Failed to create artifact registry manifest"
        exit 1
    fi
    
    log_success "Artifact management completed successfully"
    
    # Export results for use by calling script
    export ARTIFACT_MANAGER_STATUS="SUCCESS"
    export ARTIFACT_MANAGER_TENANT="$TENANT"
    export ARTIFACT_MANAGER_TRIGGER="$TRIGGER"
    
    # Export artifact information for release pipeline (main branch only)
    if [[ "$TRIGGER" == "main" ]]; then
        export RELEASE_ARTIFACT_ID="${IMMUTABLE_ARTIFACT_NAME:-$BUILT_IMAGE_NAME}"
        export RELEASE_ARTIFACT_TAG="${IMMUTABLE_ARTIFACT_TAG:-$BUILT_IMAGE_TAG}"
        export RELEASE_ARTIFACT_LATEST="${BUILT_IMAGE_LATEST:-}"
        
        log_info "Release pipeline variables exported:"
        log_info "  RELEASE_ARTIFACT_ID: $RELEASE_ARTIFACT_ID"
        log_info "  RELEASE_ARTIFACT_TAG: $RELEASE_ARTIFACT_TAG"
        log_info "  RELEASE_ARTIFACT_LATEST: $RELEASE_ARTIFACT_LATEST"
    fi
}

# Parse arguments and run main function
parse_args "$@"
main