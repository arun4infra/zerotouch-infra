#!/bin/bash
set -euo pipefail

# build.sh - Build execution helper
# Executes the actual build using existing platform CI infrastructure

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

Build execution helper using existing platform CI infrastructure.

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

# Execute build using existing platform CI infrastructure
execute_build() {
    log_step_start "Executing build using platform CI infrastructure"
    
    # Use existing platform CI master script
    local platform_ci_script="${PLATFORM_ROOT}/scripts/bootstrap/preview/tenants/scripts/in-cluster-test.sh"
    
    if [[ ! -f "$platform_ci_script" ]]; then
        log_error "Platform CI script not found: $platform_ci_script"
        return 1
    fi
    
    log_info "Platform CI configuration:"
    log_info "  Script: $platform_ci_script"
    log_info "  Trigger: $TRIGGER"
    log_info "  Event: ${GITHUB_EVENT_NAME:-unknown}"
    log_info "  Registry: ${CONTAINER_REGISTRY:-unknown}"
    log_info "  Repository: ${GITHUB_REPOSITORY:-unknown}"
    log_info "  SHA: ${GITHUB_SHA:0:8}"
    
    # Execute the platform CI script
    log_info "Executing platform CI script..."
    log_info "Running: $platform_ci_script"
    
    # Run with full output visibility
    if ! "$platform_ci_script"; then
        log_error "Platform CI execution failed"
        return 1
    fi
    
    log_step_end "Executing build using platform CI infrastructure" "SUCCESS"
    return 0
}

# Main build execution
main() {
    log_info "Starting build execution for tenant: $TENANT, trigger: $TRIGGER"
    
    # Execute build
    if ! execute_build; then
        log_error "Build execution failed"
        exit 1
    fi
    
    log_success "Build execution completed successfully"
    
    # Export results for use by calling script
    export BUILD_STATUS="SUCCESS"
    export BUILD_TENANT="$TENANT"
    export BUILD_TRIGGER="$TRIGGER"
}

# Parse arguments and run main function
parse_args "$@"
main