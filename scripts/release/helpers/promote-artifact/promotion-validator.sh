#!/bin/bash
# promotion-validator.sh - Validates artifact promotion requests

# Validate promotion request
validate_promotion() {
    log_step_start "Validating promotion request"
    
    # Validate source environment
    if ! validate_environment_name "$SOURCE_ENV"; then
        log_error "Invalid source environment: $SOURCE_ENV"
        return 1
    fi
    
    # Validate target environment
    if ! validate_environment_name "$TARGET_ENV"; then
        log_error "Invalid target environment: $TARGET_ENV"
        return 1
    fi
    
    # Ensure source and target are different
    if [[ "$SOURCE_ENV" == "$TARGET_ENV" ]]; then
        log_error "Source and target environments cannot be the same: $SOURCE_ENV"
        return 1
    fi
    
    # Validate promotion path (dev -> staging -> production)
    case "$SOURCE_ENV" in
        "dev")
            if [[ "$TARGET_ENV" != "staging" ]]; then
                log_error "Invalid promotion path: dev can only promote to staging"
                return 1
            fi
            ;;
        "staging")
            if [[ "$TARGET_ENV" != "production" ]]; then
                log_error "Invalid promotion path: staging can only promote to production"
                return 1
            fi
            ;;
        "production")
            log_error "Cannot promote from production environment"
            return 1
            ;;
    esac
    
    # Validate artifact format
    if [[ ! "$ARTIFACT" =~ ^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$ ]]; then
        log_error "Invalid artifact format: $ARTIFACT"
        log_error "Expected format: registry/image:tag"
        return 1
    fi
    
    # Check if tenant has promotion enabled
    if ! is_release_enabled; then
        log_error "Release pipeline is not enabled for tenant: $TENANT"
        return 1
    fi
    
    # Validate promotion gate requirements
    local promotion_rule
    case "$TARGET_ENV" in
        "staging")
            promotion_rule=$(get_tenant_release_config dev_to_staging)
            ;;
        "production")
            promotion_rule=$(get_tenant_release_config staging_to_production)
            ;;
    esac
    
    if [[ "$promotion_rule" == "manual" ]]; then
        log_info "Manual promotion gate required for $SOURCE_ENV -> $TARGET_ENV"
        # In a real implementation, this would check for approval
        log_warn "Manual approval check not implemented - proceeding with promotion"
    fi
    
    log_info "Promotion validation successful"
    log_info "  Tenant: $TENANT"
    log_info "  Source: $SOURCE_ENV"
    log_info "  Target: $TARGET_ENV"
    log_info "  Artifact: $ARTIFACT"
    
    log_step_end "Validating promotion request" "SUCCESS"
    return 0
}