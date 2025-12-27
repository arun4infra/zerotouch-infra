#!/bin/bash
# artifact-promoter.sh - Handles the core artifact promotion logic

# Promote artifact to target environment
promote_artifact() {
    log_step_start "Promoting artifact to target environment"
    
    log_info "Promoting artifact from $SOURCE_ENV to $TARGET_ENV"
    log_info "Artifact: $ARTIFACT"
    
    # Use the deploy-to-environment script to handle the actual deployment
    # This ensures consistency with direct deployments
    local deploy_script="${SCRIPT_DIR}/deploy-to-environment.sh"
    
    if [[ ! -f "$deploy_script" ]]; then
        log_error "Deploy script not found: $deploy_script"
        return 1
    fi
    
    log_info "Executing deployment to target environment"
    
    # Call the deployment script with the target environment and artifact
    if ! "$deploy_script" --tenant="$TENANT" --environment="$TARGET_ENV" --artifact="$ARTIFACT"; then
        log_error "Failed to deploy artifact to target environment: $TARGET_ENV"
        return 1
    fi
    
    log_success "Artifact successfully promoted to $TARGET_ENV"
    log_info "Promotion details:"
    log_info "  Source Environment: $SOURCE_ENV"
    log_info "  Target Environment: $TARGET_ENV"
    log_info "  Artifact: $ARTIFACT"
    
    # Export promotion details for use by other functions
    export PROMOTION_SOURCE="$SOURCE_ENV"
    export PROMOTION_TARGET="$TARGET_ENV"
    export PROMOTION_ARTIFACT="$ARTIFACT"
    export PROMOTION_TIMESTAMP="$(get_timestamp)"
    
    log_step_end "Promoting artifact to target environment" "SUCCESS"
    return 0
}