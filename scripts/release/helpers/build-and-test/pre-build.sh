#!/bin/bash
set -euo pipefail

# pre-build.sh - Pre-build setup and validation helper
# Sets up environment variables and validates configuration before build

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

Pre-build setup and validation helper.
Sets up environment variables for build execution.

Arguments:
  --tenant=<name>     Tenant service name (required)
  --trigger=<pr|main> Workflow trigger type (required)

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

# Setup environment variables for build
setup_build_environment() {
    log_step_start "Setting up build environment"
    
    # Set environment variables to control build mode based on trigger
    case "$TRIGGER" in
        "pr")
            # For PR: use PR mode (builds and pushes branch-sha to registry)
            export GITHUB_EVENT_NAME="pull_request"
            export GITHUB_HEAD_REF="${GITHUB_HEAD_REF:-feature/test-branch}"
            log_info "Setting up PR mode - will build and push branch-sha artifact"
            ;;
        "main")
            # For main: use prod mode (builds and pushes main-sha + latest to registry)
            export GITHUB_REF_NAME="main"
            export GITHUB_EVENT_NAME="push"
            log_info "Setting up production mode - will build and push immutable artifacts"
            ;;
    esac
    
    # Set GitHub Actions environment to enable registry push
    export GITHUB_ACTIONS="true"
    export GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-org/${TENANT}}"
    export GITHUB_REPOSITORY_OWNER="${GITHUB_REPOSITORY_OWNER:-org}"
    export GITHUB_SHA="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo 'abc123def456')}"
    export GITHUB_ACTOR="${GITHUB_ACTOR:-$(whoami)}"
    
    # Set registry configuration
    local registry
    registry=$(get_tenant_release_config registry)
    export CONTAINER_REGISTRY="$registry"
    
    log_info "Build environment configured:"
    log_info "  Tenant: $TENANT"
    log_info "  Trigger: $TRIGGER"
    log_info "  Event: ${GITHUB_EVENT_NAME}"
    log_info "  Registry: $registry"
    log_info "  Repository: ${GITHUB_REPOSITORY}"
    log_info "  SHA: ${GITHUB_SHA:0:8}"
    
    log_step_end "Setting up build environment" "SUCCESS"
    return 0
}

# Main pre-build execution
main() {
    log_info "Starting pre-build setup for tenant: $TENANT, trigger: $TRIGGER"
    
    # Setup build environment
    if ! setup_build_environment; then
        log_error "Failed to setup build environment"
        exit 1
    fi
    
    log_success "Pre-build setup completed successfully"
    
    # Export environment for use by calling script
    export PRE_BUILD_STATUS="SUCCESS"
    export PRE_BUILD_TENANT="$TENANT"
    export PRE_BUILD_TRIGGER="$TRIGGER"
}

# Parse arguments and run main function
parse_args "$@"
main