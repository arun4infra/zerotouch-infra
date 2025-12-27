#!/bin/bash
set -euo pipefail

# build-and-test.sh - Build and test execution helper script
# Handles build and test execution using preview validation mode (GitHub runners + Kind)
# Used by both PR and main branch workflows with identical infrastructure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common utilities
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config-discovery.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

# Default values
TENANT=""
TRIGGER=""

# Usage information
usage() {
    cat << EOF
Usage: $0 --tenant=<name> --trigger=<pr|main>

Build and test execution helper script for centralized release pipeline.
Uses preview validation mode with GitHub runners and Kind clusters.

Arguments:
  --tenant=<name>     Tenant service name (required)
  --trigger=<pr|main> Workflow trigger type (required)

Examples:
  $0 --tenant=deepagents-runtime --trigger=pr
  $0 --tenant=deepagents-runtime --trigger=main

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

# Execute build and test using modular helper scripts
execute_modular_build_test() {
    log_step_start "Executing modular build and test"
    
    local helpers_dir="${SCRIPT_DIR}/helpers/build-and-test"
    
    # Pre-build setup
    log_info "Running pre-build setup..."
    if ! "${helpers_dir}/pre-build.sh" --tenant="$TENANT" --trigger="$TRIGGER"; then
        log_error "Pre-build setup failed"
        return 1
    fi
    
    # Build execution
    log_info "Running build execution..."
    if ! "${helpers_dir}/build.sh" --tenant="$TENANT" --trigger="$TRIGGER"; then
        log_error "Build execution failed"
        return 1
    fi
    
    # Post-build processing
    log_info "Running post-build processing..."
    if ! "${helpers_dir}/post-build.sh" --tenant="$TENANT" --trigger="$TRIGGER"; then
        log_error "Post-build processing failed"
        return 1
    fi
    
    log_step_end "Executing modular build and test" "SUCCESS"
    return 0
}

# Main build and test execution
main() {
    local start_time
    start_time=$(date +%s)
    
    log_phase "BUILD AND TEST PHASE"
    log_info "Starting build and test for tenant: $TENANT, trigger: $TRIGGER"
    
    # Initialize logging
    init_logging "$TENANT" "build-test"
    
    # Log environment information
    log_environment
    
    # Execute modular build and test using helper scripts
    if ! execute_modular_build_test; then
        log_error "Modular build and test execution failed"
        exit 1
    fi
    
    local end_time
    local duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    log_success "Build and test completed successfully for tenant: $TENANT"
    log_info "Duration: ${duration}s"
    
    # Export results for use by calling script
    export BUILD_TEST_STATUS="SUCCESS"
    export BUILD_TEST_DURATION="$duration"
    export BUILD_TEST_IMAGE="$BUILT_IMAGE_NAME"
    export BUILD_TEST_TAG="$BUILT_IMAGE_TAG"
    
    # For main branch, also export the latest tag
    if [[ "$TRIGGER" == "main" && -n "${BUILT_IMAGE_LATEST:-}" ]]; then
        export BUILD_TEST_LATEST="$BUILT_IMAGE_LATEST"
    fi
}

# Parse arguments and run main function
parse_args "$@"
main