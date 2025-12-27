#!/bin/bash
# release-validator.sh - Validates release pipeline environment and prerequisites

# Validate release pipeline environment
validate_release_environment() {
    log_step_start "Validating release pipeline environment"
    
    # Validate environment name
    if ! validate_environment_name "$ENVIRONMENT"; then
        return 1
    fi
    
    # Check required environment variables
    if [[ -z "${BOT_GITHUB_TOKEN:-}" ]]; then
        log_error "BOT_GITHUB_TOKEN environment variable is required for tenant repository access"
        return 1
    fi
    
    # Check Git is available
    if ! check_command git; then
        return 1
    fi
    
    # Validate tenant has release pipeline enabled (now that config is discovered)
    if ! is_release_enabled; then
        log_error "Release pipeline is not enabled for tenant: $TENANT"
        return 1
    fi
    
    # Validate artifact if provided
    if [[ -n "$ARTIFACT" ]]; then
        if [[ ! "$ARTIFACT" =~ ^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$ ]]; then
            log_error "Invalid artifact format: $ARTIFACT"
            log_error "Expected format: registry/image:tag"
            return 1
        fi
    fi
    
    log_info "Release environment validation successful"
    log_info "  Tenant: $TENANT"
    log_info "  Environment: $ENVIRONMENT"
    log_info "  Artifact: ${ARTIFACT:-'(will use latest)'}"
    
    log_step_end "Validating release pipeline environment" "SUCCESS"
    return 0
}