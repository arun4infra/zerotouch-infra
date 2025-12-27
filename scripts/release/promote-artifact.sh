#!/bin/bash
set -euo pipefail

# promote-artifact.sh - Artifact promotion orchestrator
# Promotes artifacts between environments using GitOps approach

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common utilities
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config-discovery.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

# Source promote-artifact helper modules
source "${SCRIPT_DIR}/helpers/promote-artifact/promotion-validator.sh"
source "${SCRIPT_DIR}/helpers/promote-artifact/artifact-promoter.sh"
source "${SCRIPT_DIR}/helpers/promote-artifact/promotion-recorder.sh"

# Default values
TENANT=""
SOURCE_ENV=""
TARGET_ENV=""
ARTIFACT=""

# Usage information
usage() {
    cat << EOF
Usage: $0 --tenant=<name> --source=<env> --target=<env> --artifact=<id>

Artifact promotion orchestrator that promotes artifacts between environments.
Uses GitOps approach to update tenant repository manifests.

Arguments:
  --tenant=<name>        Tenant service name (required)
  --source=<env>         Source environment (dev|staging|production) (required)
  --target=<env>         Target environment (dev|staging|production) (required)
  --artifact=<id>        Artifact ID to promote (required)

Examples:
  $0 --tenant=deepagents-runtime --source=dev --target=staging --artifact=ghcr.io/org/deepagents-runtime:main-abc123
  $0 --tenant=deepagents-runtime --source=staging --target=production --artifact=ghcr.io/org/deepagents-runtime:main-abc123

Environment Variables:
  BOT_GITHUB_TOKEN       GitHub token for tenant repository access

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
            --source=*)
                SOURCE_ENV="${1#*=}"
                shift
                ;;
            --target=*)
                TARGET_ENV="${1#*=}"
                shift
                ;;
            --artifact=*)
                ARTIFACT="${1#*=}"
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

    if [[ -z "$SOURCE_ENV" ]]; then
        log_error "Source environment is required (--source=<env>)"
        usage
        exit 1
    fi

    if [[ -z "$TARGET_ENV" ]]; then
        log_error "Target environment is required (--target=<env>)"
        usage
        exit 1
    fi

    if [[ -z "$ARTIFACT" ]]; then
        log_error "Artifact ID is required (--artifact=<id>)"
        usage
        exit 1
    fi
}

# Main promotion orchestration
main() {
    local start_time
    start_time=$(date +%s)
    
    log_phase "ARTIFACT PROMOTION PHASE"
    log_info "Starting artifact promotion for tenant: $TENANT"
    
    # Initialize logging
    init_logging "$TENANT" "promote-artifact"
    
    # Log environment information
    log_environment
    
    # Discover tenant configuration
    if ! discover_tenant_config "$TENANT"; then
        log_error "Failed to discover tenant configuration"
        exit 1
    fi
    
    # Step 1: Validate promotion request
    if ! validate_promotion; then
        log_error "Promotion validation failed"
        exit 1
    fi
    
    # Step 2: Promote artifact to target environment
    if ! promote_artifact; then
        log_error "Failed to promote artifact"
        exit 1
    fi
    
    # Step 3: Record promotion history
    if ! record_promotion; then
        log_error "Failed to record promotion"
        exit 1
    fi
    
    local end_time
    local duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    log_success "Artifact promotion completed successfully"
    log_info "Tenant: $TENANT"
    log_info "Promotion: $SOURCE_ENV -> $TARGET_ENV"
    log_info "Artifact: $ARTIFACT"
    log_info "Duration: ${duration}s"
    
    # Export results for use by calling script
    export PROMOTION_STATUS="SUCCESS"
    export PROMOTION_DURATION="$duration"
}

# Parse arguments and run main function
parse_args "$@"
main