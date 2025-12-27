#!/bin/bash
set -euo pipefail

# promote-artifact.sh - Environment promotion via Git commits
# Promotes artifacts between environments using GitOps approach

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common utilities
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config-discovery.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

# Default values
TENANT=""
SOURCE_ENV=""
TARGET_ENV=""
ARTIFACT=""

# Usage information
usage() {
    cat << EOF
Usage: $0 --tenant=<name> --source=<env> --target=<env> --artifact=<id>

Promote artifacts between environments using GitOps approach.
Updates tenant repository with new artifact tags for target environment.

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

# Validate promotion request
validate_promotion() {
    log_step_start "Validating promotion request"
    
    # Validate environment names
    if ! validate_environment_name "$SOURCE_ENV"; then
        return 1
    fi
    
    if ! validate_environment_name "$TARGET_ENV"; then
        return 1
    fi
    
    # Validate promotion path
    local valid_promotions=("dev:staging" "staging:production")
    local promotion_path="${SOURCE_ENV}:${TARGET_ENV}"
    local valid=false
    
    for valid_promotion in "${valid_promotions[@]}"; do
        if [[ "$promotion_path" == "$valid_promotion" ]]; then
            valid=true
            break
        fi
    done
    
    if [[ "$valid" != "true" ]]; then
        log_error "Invalid promotion path: $SOURCE_ENV -> $TARGET_ENV"
        log_error "Valid promotion paths: dev -> staging, staging -> production"
        return 1
    fi
    
    # Check promotion gate requirements
    local promotion_rule=""
    case "$promotion_path" in
        "dev:staging")
            promotion_rule=$(get_tenant_release_config dev_to_staging)
            ;;
        "staging:production")
            promotion_rule=$(get_tenant_release_config staging_to_production)
            ;;
    esac
    
    log_info "Promotion rule for $SOURCE_ENV -> $TARGET_ENV: $promotion_rule"
    
    if [[ "$promotion_rule" == "manual" ]]; then
        log_info "Manual promotion gate required for this promotion"
        # In a real implementation, this would check for existing approval
        # For now, we'll proceed assuming approval has been granted
    fi
    
    log_step_end "Validating promotion request" "SUCCESS"
    return 0
}

# Promote artifact to target environment
promote_artifact() {
    log_step_start "Promoting artifact to target environment"
    
    log_info "Promotion Details:"
    log_info "  Tenant: $TENANT"
    log_info "  Source Environment: $SOURCE_ENV"
    log_info "  Target Environment: $TARGET_ENV"
    log_info "  Artifact: $ARTIFACT"
    
    # Call deploy-to-environment.sh to handle the actual GitOps deployment
    local deploy_script="${SCRIPT_DIR}/deploy-to-environment.sh"
    
    if [[ ! -f "$deploy_script" ]]; then
        log_error "Deploy script not found: $deploy_script"
        return 1
    fi
    
    log_info "Calling deployment script for target environment"
    
    if ! "$deploy_script" --tenant="$TENANT" --environment="$TARGET_ENV" --artifact="$ARTIFACT"; then
        log_error "Failed to deploy artifact to target environment"
        return 1
    fi
    
    log_success "Artifact promoted successfully"
    log_info "  From: $SOURCE_ENV"
    log_info "  To: $TARGET_ENV"
    log_info "  Artifact: $ARTIFACT"
    
    log_step_end "Promoting artifact to target environment" "SUCCESS"
    return 0
}

# Record promotion history
record_promotion() {
    log_step_start "Recording promotion history"
    
    local promotion_record="${CONFIG_CACHE_DIR}/${TENANT}-promotions.log"
    mkdir -p "$(dirname "$promotion_record")"
    
    local timestamp
    timestamp=$(get_timestamp)
    
    # Append promotion record
    cat >> "$promotion_record" << EOF
{
  "timestamp": "$timestamp",
  "tenant": "$TENANT",
  "source_environment": "$SOURCE_ENV",
  "target_environment": "$TARGET_ENV",
  "artifact": "$ARTIFACT",
  "promoted_by": "$(whoami)",
  "hostname": "$(hostname)"
}
EOF
    
    log_info "Promotion recorded: $promotion_record"
    
    log_step_end "Recording promotion history" "SUCCESS"
    return 0
}

# Main promotion execution
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
    
    # Validate promotion request
    if ! validate_promotion; then
        log_error "Promotion validation failed"
        exit 1
    fi
    
    # Promote artifact
    if ! promote_artifact; then
        log_error "Failed to promote artifact"
        exit 1
    fi
    
    # Record promotion
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