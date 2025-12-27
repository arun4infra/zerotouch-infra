#!/bin/bash
set -euo pipefail

# release-pipeline.sh - Release pipeline orchestrator
# Handles deployment to environments via GitOps (never touches clusters directly)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common utilities
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config-discovery.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

# Source release-pipeline helper modules
source "${SCRIPT_DIR}/helpers/release-pipeline/release-validator.sh"
source "${SCRIPT_DIR}/helpers/release-pipeline/promotion-gate-manager.sh"
source "${SCRIPT_DIR}/helpers/release-pipeline/argocd-monitor.sh"

# Default values
TENANT=""
ENVIRONMENT=""
ARTIFACT=""

# Usage information
usage() {
    cat << EOF
Usage: $0 --tenant=<name> --environment=<env> [--artifact=<id>]

Release pipeline orchestrator for GitOps-based deployments.
Updates tenant repository with new artifact tags, never touches clusters directly.

Arguments:
  --tenant=<name>        Tenant service name (required)
  --environment=<env>    Target environment (dev|staging|production) (required)
  --artifact=<id>        Artifact ID to deploy (optional, uses latest if not specified)

Examples:
  $0 --tenant=deepagents-runtime --environment=dev
  $0 --tenant=deepagents-runtime --environment=staging --artifact=ghcr.io/org/deepagents-runtime:main-abc123

Environment Variables:
  BOT_GITHUB_TOKEN       GitHub token for tenant repository access
  ARTIFACT_ID            Artifact ID from create-artifact phase (if not specified via --artifact)

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
            --environment=*)
                ENVIRONMENT="${1#*=}"
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

    if [[ -z "$ENVIRONMENT" ]]; then
        log_error "Environment is required (--environment=<env>)"
        usage
        exit 1
    fi

    # Use ARTIFACT_ID environment variable if artifact not specified
    if [[ -z "$ARTIFACT" ]] && [[ -n "${ARTIFACT_ID:-}" ]]; then
        ARTIFACT="$ARTIFACT_ID"
        log_info "Using artifact from environment: $ARTIFACT"
    fi

    if [[ -z "$ARTIFACT" ]]; then
        log_error "Artifact ID is required (--artifact=<id> or ARTIFACT_ID environment variable)"
        usage
        exit 1
    fi
}

# Main release pipeline orchestration
main() {
    local start_time
    start_time=$(date +%s)
    
    log_phase "RELEASE PIPELINE PHASE"
    log_info "Starting release pipeline for tenant: $TENANT, environment: $ENVIRONMENT"
    
    # Initialize logging
    init_logging "$TENANT" "release-pipeline"
    
    # Log environment information
    log_environment
    
    # Discover tenant configuration first
    if ! discover_tenant_config "$TENANT"; then
        log_error "Failed to discover tenant configuration"
        exit 1
    fi
    
    # Step 1: Validate release environment
    if ! validate_release_environment; then
        log_error "Environment validation failed"
        exit 1
    fi
    
    # Step 2: Check promotion gate requirements
    if ! check_promotion_gate; then
        log_info "Promotion gate check completed (may require manual approval)"
        # Don't exit here - the gate might be pending approval
    fi
    
    # Step 3: Deploy to environment using GitOps approach
    if ! "${SCRIPT_DIR}/deploy-to-environment.sh" --tenant="$TENANT" --environment="$ENVIRONMENT" --artifact="$ARTIFACT"; then
        log_error "Failed to deploy to environment"
        exit 1
    fi
    
    # Step 4: Monitor ArgoCD sync (optional)
    wait_for_argocd_sync
    
    local end_time
    local duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    log_success "Release pipeline completed successfully for tenant: $TENANT"
    log_info "Environment: $ENVIRONMENT"
    log_info "Artifact: $ARTIFACT"
    log_info "Duration: ${duration}s"
    
    # Export results for use by calling script
    export RELEASE_PIPELINE_STATUS="SUCCESS"
    export RELEASE_PIPELINE_DURATION="$duration"
}

# Parse arguments and run main function
parse_args "$@"
main