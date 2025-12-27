#!/bin/bash
set -euo pipefail

# ci-pipeline.sh - Main CI orchestration script
# Handles both PR and main branch workflows with identical infrastructure (GitHub runners + Kind)
# Calls helper scripts for specific tasks

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common utilities
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config-discovery.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

# Default values
TENANT=""
TRIGGER=""
VERBOSE=false

# Usage information
usage() {
    cat << EOF
Usage: $0 --tenant=<name> --trigger=<pr|main> [options]

Main CI orchestration script for centralized release pipeline.
Handles both PR and main branch workflows using identical infrastructure.

Arguments:
  --tenant=<name>     Tenant service name (required)
  --trigger=<pr|main> Workflow trigger type (required)

Options:
  --verbose           Enable verbose logging
  --help             Show this help message

Examples:
  $0 --tenant=deepagents-runtime --trigger=pr
  $0 --tenant=deepagents-runtime --trigger=main --verbose

Environment Variables:
  BOT_GITHUB_TOKEN    GitHub token for tenant repository access
  AWS_ACCESS_KEY_ID   AWS credentials for configuration discovery
  AWS_SECRET_ACCESS_KEY
  AWS_SESSION_TOKEN   (for OIDC authentication)

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
            --verbose)
                VERBOSE=true
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

    if [[ "$TRIGGER" != "pr" && "$TRIGGER" != "main" ]]; then
        log_error "Trigger must be 'pr' or 'main', got: $TRIGGER"
        usage
        exit 1
    fi
}

# Validate environment and prerequisites
validate_environment() {
    log_info "Validating environment for tenant: $TENANT, trigger: $TRIGGER"

    # Check required environment variables
    local required_vars=("BOT_GITHUB_TOKEN")
    
    # AWS credentials required for configuration discovery
    if [[ -n "${AWS_SESSION_TOKEN:-}" ]]; then
        # OIDC authentication (GitHub Actions)
        required_vars+=("AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_SESSION_TOKEN")
    else
        # Standard AWS credentials
        required_vars+=("AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY")
    fi

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required environment variable not set: $var"
            exit 1
        fi
    done

    # Validate platform structure
    if [[ ! -d "$PLATFORM_ROOT" ]]; then
        log_error "Platform root directory not found: $PLATFORM_ROOT"
        exit 1
    fi

    log_info "Environment validation completed successfully"
}

# Main CI pipeline execution
main() {
    log_info "Starting CI pipeline for tenant: $TENANT, trigger: $TRIGGER"
    
    # Set verbose logging if requested
    if [[ "$VERBOSE" == "true" ]]; then
        export LOG_LEVEL="debug"
    fi

    # Validate environment
    validate_environment

    # Discover and validate tenant configuration
    log_info "Discovering tenant configuration..."
    if ! discover_tenant_config "$TENANT"; then
        log_error "Failed to discover tenant configuration"
        exit 1
    fi

    # Validate configuration
    log_info "Validating tenant configuration..."
    if ! validate_tenant_config "$TENANT"; then
        log_error "Tenant configuration validation failed"
        exit 1
    fi

    # Execute build and test phase (identical for both PR and main branch)
    log_info "Executing build and test phase..."
    if ! "${SCRIPT_DIR}/build-and-test.sh" --tenant="$TENANT" --trigger="$TRIGGER"; then
        log_error "Build and test phase failed"
        exit 1
    fi

    # Handle trigger-specific logic
    case "$TRIGGER" in
        "pr")
            log_info "PR workflow: Build, test, and provide feedback only"
            log_info "✅ PR testing completed successfully"
            log_info "📦 Preview artifact available: ${BUILD_TEST_IMAGE:-unknown}"
            log_info "🚫 No deployment to persistent environments (PR restriction)"
            log_info "💬 Feedback provided - ready for review"
            
            # Ensure no deployment variables are exported for PR workflows
            export PR_WORKFLOW="true"
            export DEPLOYMENT_ALLOWED="false"
            ;;
        "main")
            log_info "Main branch workflow: Build, test, and create immutable artifacts"
            log_info "✅ Main branch testing completed successfully"
            log_info "📦 Immutable artifacts created:"
            log_info "    Primary: ${BUILD_TEST_IMAGE:-unknown}"
            log_info "    Latest: ${BUILD_TEST_LATEST:-unknown}"
            
            # Verify artifact information is available for release pipeline
            if [[ -z "${ARTIFACT_ID:-}" ]]; then
                log_error "ARTIFACT_ID not set by post-build processing"
                exit 1
            fi
            
            log_info "🚀 Triggering release pipeline for deployment..."
            
            # Trigger release pipeline for deployment to dev environment
            if ! "${SCRIPT_DIR}/release-pipeline.sh" --tenant="$TENANT" --environment="dev" --artifact="$ARTIFACT_ID"; then
                log_error "Release pipeline failed"
                exit 1
            fi

            log_info "✅ Main branch workflow completed successfully"
            log_info "🎯 Immutable artifacts ready for multi-environment deployment"
            
            export MAIN_BRANCH_WORKFLOW="true"
            export DEPLOYMENT_ALLOWED="true"
            ;;
    esac

    log_info "CI pipeline completed successfully for tenant: $TENANT"
}

# Parse arguments and run main function
parse_args "$@"
main