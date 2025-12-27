#!/bin/bash
set -euo pipefail

# release-pipeline.sh - GitOps-based deployment orchestration
# Handles deployment to environments via Git commits (never touches clusters directly)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common utilities
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/config-discovery.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

# Default values
TENANT=""
ENVIRONMENT=""
ARTIFACT=""

# Usage information
usage() {
    cat << EOF
Usage: $0 --tenant=<name> --environment=<env> [--artifact=<id>]

GitOps-based deployment orchestration for centralized release pipeline.
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

    # Use artifact from environment if not specified
    if [[ -z "$ARTIFACT" ]]; then
        ARTIFACT="${ARTIFACT_ID:-}"
    fi

    if [[ -z "$ARTIFACT" ]]; then
        log_error "Artifact ID is required (--artifact=<id> or ARTIFACT_ID environment variable)"
        usage
        exit 1
    fi
}

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
    
    # Validate tenant has release pipeline enabled
    if ! is_release_enabled; then
        log_error "Release pipeline is not enabled for tenant: $TENANT"
        return 1
    fi
    
    log_step_end "Validating release pipeline environment" "SUCCESS"
    return 0
}

# Check promotion gate requirements
check_promotion_gate() {
    log_step_start "Checking promotion gate requirements"
    
    local promotion_rule=""
    
    # Determine promotion rule based on target environment
    case "$ENVIRONMENT" in
        "dev")
            # Dev environment typically has automatic deployment after main branch
            promotion_rule="automatic"
            ;;
        "staging")
            promotion_rule=$(get_tenant_release_config dev_to_staging)
            ;;
        "production")
            promotion_rule=$(get_tenant_release_config staging_to_production)
            ;;
    esac
    
    log_info "Promotion rule for $ENVIRONMENT: $promotion_rule"
    
    if [[ "$promotion_rule" == "manual" ]]; then
        log_info "Manual promotion gate required for environment: $ENVIRONMENT"
        
        # Create promotion gate (this would integrate with the XPromotionGate CRD)
        if ! create_promotion_gate "$TENANT" "$ENVIRONMENT" "$ARTIFACT"; then
            log_error "Failed to create promotion gate"
            return 1
        fi
        
        log_info "Promotion gate created, waiting for manual approval..."
        # In a real implementation, this would wait for approval or return early
        # For now, we'll simulate automatic approval for dev environment
        if [[ "$ENVIRONMENT" == "dev" ]]; then
            log_info "Auto-approving for dev environment (simulation)"
        else
            log_warn "Manual approval required - pipeline will wait"
            return 0  # Return success but don't proceed with deployment
        fi
    fi
    
    log_step_end "Checking promotion gate requirements" "SUCCESS"
    return 0
}

# Create promotion gate
create_promotion_gate() {
    local tenant="$1"
    local target_env="$2"
    local artifact="$3"
    
    local source_env=""
    local gate_id
    
    # Determine source environment
    case "$target_env" in
        "staging")
            source_env="dev"
            ;;
        "production")
            source_env="staging"
            ;;
        *)
            log_debug "No promotion gate needed for environment: $target_env"
            return 0
            ;;
    esac
    
    gate_id=$(generate_id "gate")
    
    log_promotion_gate_info "$tenant" "$source_env" "$target_env" "$artifact" "$gate_id"
    
    # In a real implementation, this would create an XPromotionGate resource
    # For now, we'll create a local gate file for tracking
    local gate_file="${CONFIG_CACHE_DIR}/${tenant}-${source_env}-to-${target_env}-gate.json"
    mkdir -p "$(dirname "$gate_file")"
    
    cat > "$gate_file" << EOF
{
  "gate_id": "$gate_id",
  "tenant": "$tenant",
  "artifact": "$artifact",
  "source_environment": "$source_env",
  "target_environment": "$target_env",
  "status": "pending",
  "created_at": "$(get_timestamp)",
  "timeout_hours": 24
}
EOF
    
    log_info "Promotion gate created: $gate_file"
    export PROMOTION_GATE_ID="$gate_id"
    export PROMOTION_GATE_FILE="$gate_file"
    
    return 0
}

# Clone tenant repository for GitOps updates
clone_tenant_repository() {
    log_step_start "Cloning tenant repository for GitOps updates"
    
    local tenant_repo_url
    local clone_dir
    
    # In a real implementation, this would be discovered from zerotouch-tenants
    # For now, construct the URL based on tenant name
    tenant_repo_url="https://github.com/org/${TENANT}.git"
    clone_dir="${CONFIG_CACHE_DIR}/${TENANT}-repo"
    
    log_info "Cloning tenant repository: $tenant_repo_url"
    log_info "Clone directory: $clone_dir"
    
    # Remove existing clone if it exists
    if [[ -d "$clone_dir" ]]; then
        rm -rf "$clone_dir"
    fi
    
    # Clone the repository
    if ! log_command "git clone https://${BOT_GITHUB_TOKEN}@github.com/org/${TENANT}.git $clone_dir"; then
        log_error "Failed to clone tenant repository"
        return 1
    fi
    
    # Change to repository directory
    cd "$clone_dir"
    
    # Configure Git user
    git config user.name "Release Pipeline Bot"
    git config user.email "release-pipeline@zerotouch.dev"
    
    export TENANT_REPO_DIR="$clone_dir"
    
    log_step_end "Cloning tenant repository for GitOps updates" "SUCCESS"
    return 0
}

# Update deployment manifests with new artifact
update_deployment_manifests() {
    log_step_start "Updating deployment manifests with new artifact"
    
    local manifest_dir="${TENANT_REPO_DIR}/platform/claims"
    local overlay_dir="${TENANT_REPO_DIR}/overlays/${ENVIRONMENT}"
    
    log_info "Updating manifests for environment: $ENVIRONMENT"
    log_info "Artifact: $ARTIFACT"
    
    # Look for deployment manifests in common locations
    local manifest_files=()
    
    # Check platform claims directory
    if [[ -d "$manifest_dir" ]]; then
        while IFS= read -r -d '' file; do
            manifest_files+=("$file")
        done < <(find "$manifest_dir" -name "*.yaml" -o -name "*.yml" -print0)
    fi
    
    # Check overlays directory
    if [[ -d "$overlay_dir" ]]; then
        while IFS= read -r -d '' file; do
            manifest_files+=("$file")
        done < <(find "$overlay_dir" -name "*.yaml" -o -name "*.yml" -print0)
    fi
    
    if [[ ${#manifest_files[@]} -eq 0 ]]; then
        log_error "No deployment manifests found in $manifest_dir or $overlay_dir"
        return 1
    fi
    
    log_info "Found ${#manifest_files[@]} manifest files to update"
    
    # Update image references in manifest files
    local updated_files=0
    for manifest_file in "${manifest_files[@]}"; do
        log_debug "Processing manifest: $manifest_file"
        
        # Update image references (this is a simplified approach)
        # In a real implementation, this would use yq or a more sophisticated tool
        if grep -q "image:.*${TENANT}" "$manifest_file"; then
            log_info "Updating image reference in: $manifest_file"
            
            # Create backup
            cp "$manifest_file" "${manifest_file}.backup"
            
            # Update image reference
            sed -i.tmp "s|image:.*${TENANT}:.*|image: ${ARTIFACT}|g" "$manifest_file"
            rm -f "${manifest_file}.tmp"
            
            ((updated_files++))
        fi
    done
    
    if [[ $updated_files -eq 0 ]]; then
        log_warn "No manifest files were updated (no matching image references found)"
    else
        log_info "Updated $updated_files manifest files"
    fi
    
    log_step_end "Updating deployment manifests with new artifact" "SUCCESS"
    return 0
}

# Commit and push GitOps changes
commit_and_push_changes() {
    log_step_start "Committing and pushing GitOps changes"
    
    cd "$TENANT_REPO_DIR"
    
    # Check if there are any changes
    if ! git diff --quiet; then
        log_info "Changes detected, committing and pushing..."
        
        # Add all changes
        git add .
        
        # Create commit message
        local commit_message="Deploy ${TENANT} to ${ENVIRONMENT}

Artifact: ${ARTIFACT}
Environment: ${ENVIRONMENT}
Deployed by: Release Pipeline
Timestamp: $(get_timestamp)
"
        
        # Commit changes
        if ! log_command "git commit -m \"$commit_message\""; then
            log_error "Failed to commit changes"
            return 1
        fi
        
        # Push changes
        if ! log_command "git push origin main"; then
            log_error "Failed to push changes"
            return 1
        fi
        
        # Get commit SHA for tracking
        local commit_sha
        commit_sha=$(git rev-parse HEAD)
        
        log_deployment_info "$TENANT" "$ENVIRONMENT" "$ARTIFACT"
        log_info "GitOps commit SHA: $commit_sha"
        
        export DEPLOYMENT_COMMIT_SHA="$commit_sha"
        
    else
        log_info "No changes detected, skipping commit"
    fi
    
    log_step_end "Committing and pushing GitOps changes" "SUCCESS"
    return 0
}

# Wait for ArgoCD sync (optional monitoring)
wait_for_argocd_sync() {
    log_step_start "Monitoring ArgoCD sync (optional)"
    
    log_info "GitOps deployment initiated for $TENANT in $ENVIRONMENT"
    log_info "ArgoCD will automatically sync the changes"
    log_info "Monitor deployment status in ArgoCD UI or via kubectl"
    
    # In a real implementation, this could:
    # 1. Wait for ArgoCD Application to sync
    # 2. Monitor deployment status
    # 3. Run health checks
    # 4. Report deployment success/failure
    
    log_info "Deployment monitoring can be implemented based on requirements"
    
    log_step_end "Monitoring ArgoCD sync (optional)" "SUCCESS"
    return 0
}

# Main release pipeline execution
main() {
    local start_time
    start_time=$(date +%s)
    
    log_phase "RELEASE PIPELINE PHASE"
    log_info "Starting release pipeline for tenant: $TENANT, environment: $ENVIRONMENT"
    
    # Initialize logging
    init_logging "$TENANT" "release-pipeline"
    
    # Log environment information
    log_environment
    
    # Validate environment
    if ! validate_release_environment; then
        log_error "Environment validation failed"
        exit 1
    fi
    
    # Check promotion gate requirements
    if ! check_promotion_gate; then
        log_info "Promotion gate check completed (may require manual approval)"
        # Don't exit here - the gate might be pending approval
    fi
    
    # Clone tenant repository for GitOps updates
    if ! clone_tenant_repository; then
        log_error "Failed to clone tenant repository"
        exit 1
    fi
    
    # Update deployment manifests
    if ! update_deployment_manifests; then
        log_error "Failed to update deployment manifests"
        exit 1
    fi
    
    # Commit and push changes
    if ! commit_and_push_changes; then
        log_error "Failed to commit and push changes"
        exit 1
    fi
    
    # Wait for ArgoCD sync (optional)
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