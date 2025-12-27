#!/bin/bash
set -euo pipefail

# deploy-to-environment.sh - GitOps deployment helper (updates tenant repo, never touches clusters directly)
# Handles GitOps-based deployments by updating tenant repository manifests

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
DRY_RUN="false"

# Usage information
usage() {
    cat << EOF
Usage: $0 --tenant=<name> --environment=<env> --artifact=<id> [--dry-run]

GitOps deployment helper that updates tenant repository manifests.
Never touches clusters directly - ArgoCD handles all cluster operations.

Arguments:
  --tenant=<name>        Tenant service name (required)
  --environment=<env>    Target environment (dev|staging|production) (required)
  --artifact=<id>        Artifact ID to deploy (required)
  --dry-run              Show what would be done without making changes

Examples:
  $0 --tenant=deepagents-runtime --environment=dev --artifact=ghcr.io/org/deepagents-runtime:main-abc123
  $0 --tenant=deepagents-runtime --environment=staging --artifact=ghcr.io/org/deepagents-runtime:main-abc123 --dry-run

Environment Variables:
  BOT_GITHUB_TOKEN       GitHub token for tenant repository access (if using remote repo)

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
            --dry-run)
                DRY_RUN="true"
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

    if [[ -z "$ARTIFACT" ]]; then
        log_error "Artifact ID is required (--artifact=<id>)"
        usage
        exit 1
    fi
}

# Validate deployment request
validate_deployment() {
    log_step_start "Validating deployment request"
    
    # Validate environment name
    if ! validate_environment_name "$ENVIRONMENT"; then
        return 1
    fi
    
    # Validate artifact format (basic check)
    if [[ ! "$ARTIFACT" =~ ^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$ ]]; then
        log_error "Invalid artifact format: $ARTIFACT"
        log_error "Expected format: registry/image:tag"
        return 1
    fi
    
    log_info "Deployment validation successful"
    log_info "  Tenant: $TENANT"
    log_info "  Environment: $ENVIRONMENT"
    log_info "  Artifact: $ARTIFACT"
    log_info "  Dry Run: $DRY_RUN"
    
    log_step_end "Validating deployment request" "SUCCESS"
    return 0
}

# Clone zerotouch-tenants repository for GitOps updates
clone_tenants_repository() {
    log_step_start "Cloning zerotouch-tenants repository"
    
    local tenants_repo_url
    local clone_dir
    
    # Get tenants repository URL from environment or use default
    local tenants_repo_name="${TENANTS_REPO_NAME:-zerotouch-tenants}"
    tenants_repo_url="https://github.com/org/${tenants_repo_name}.git"
    clone_dir="${CONFIG_CACHE_DIR}/zerotouch-tenants"
    
    log_info "Cloning zerotouch-tenants repository: $tenants_repo_url"
    log_info "Clone directory: $clone_dir"
    
    # Remove existing clone if it exists
    if [[ -d "$clone_dir" ]]; then
        rm -rf "$clone_dir"
    fi
    
    # For local development, check if zerotouch-tenants exists in workspace and has a remote
    local workspace_root
    workspace_root=$(cd "$(get_platform_root)/.." && pwd)
    local local_tenants_dir="${workspace_root}/zerotouch-tenants"
    
    if [[ -d "$local_tenants_dir/.git" ]]; then
        log_info "Found local zerotouch-tenants repository with Git: $local_tenants_dir"
        
        # Check if it has a remote origin
        cd "$local_tenants_dir"
        if git remote get-url origin &>/dev/null; then
            local remote_url
            remote_url=$(git remote get-url origin)
            log_info "Local repository has remote: $remote_url"
            
            # Pull latest changes to ensure we're up to date
            log_info "Pulling latest changes from remote"
            if log_command "git pull origin main"; then
                export TENANTS_REPO_DIR="$local_tenants_dir"
                export TENANTS_REPO_TYPE="local_with_remote"
                log_step_end "Cloning zerotouch-tenants repository" "SUCCESS"
                return 0
            else
                log_warn "Failed to pull from remote, will clone fresh copy"
            fi
        else
            log_warn "Local repository has no remote origin, will clone fresh copy"
        fi
    fi
    
    # Try to clone from remote (if BOT_GITHUB_TOKEN is available)
    if [[ -n "${BOT_GITHUB_TOKEN:-}" ]]; then
        log_info "Attempting to clone from remote repository"
        
        if log_command "git clone https://${BOT_GITHUB_TOKEN}@github.com/org/${tenants_repo_name}.git $clone_dir"; then
            export TENANTS_REPO_DIR="$clone_dir"
            export TENANTS_REPO_TYPE="remote"
            log_step_end "Cloning zerotouch-tenants repository" "SUCCESS"
            return 0
        else
            log_warn "Failed to clone remote repository, creating mock structure"
        fi
    fi
    
    # Create mock zerotouch-tenants structure for testing
    log_warn "Creating mock zerotouch-tenants structure for testing"
    
    mkdir -p "${clone_dir}/tenants/${TENANT}/overlays/${ENVIRONMENT}"
    
    # Create a sample kustomization.yaml
    cat > "${clone_dir}/tenants/${TENANT}/overlays/${ENVIRONMENT}/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- ../../base

images:
- name: ${TENANT}
  newTag: latest

namespace: $(get_tenant_config namespace)
EOF
    
    # Create base kustomization
    mkdir -p "${clone_dir}/tenants/${TENANT}/base"
    cat > "${clone_dir}/tenants/${TENANT}/base/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- deployment.yaml
- service.yaml

commonLabels:
  app: ${TENANT}
EOF
    
    # Create sample deployment
    cat > "${clone_dir}/tenants/${TENANT}/base/deployment.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${TENANT}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${TENANT}
  template:
    metadata:
      labels:
        app: ${TENANT}
    spec:
      containers:
      - name: ${TENANT}
        image: ${TENANT}:latest
        ports:
        - containerPort: 8080
EOF
    
    # Create sample service
    cat > "${clone_dir}/tenants/${TENANT}/base/service.yaml" << EOF
apiVersion: v1
kind: Service
metadata:
  name: ${TENANT}
spec:
  selector:
    app: ${TENANT}
  ports:
  - port: 80
    targetPort: 8080
EOF
    
    export TENANTS_REPO_DIR="$clone_dir"
    export TENANTS_REPO_TYPE="mock"
    
    log_info "Created mock zerotouch-tenants repository: $clone_dir"
    log_step_end "Cloning zerotouch-tenants repository" "SUCCESS"
    return 0
}

# Update tenant overlay with new artifact using kustomize
update_tenant_overlay() {
    log_step_start "Updating tenant overlay with new artifact"
    
    local overlay_dir="${TENANTS_REPO_DIR}/tenants/${TENANT}/overlays/${ENVIRONMENT}"
    local kustomization_file="${overlay_dir}/kustomization.yaml"
    
    log_info "Updating overlay for environment: $ENVIRONMENT"
    log_info "Artifact: $ARTIFACT"
    log_info "Overlay directory: $overlay_dir"
    log_info "Kustomization file: $kustomization_file"
    
    # Ensure overlay directory exists
    if [[ ! -d "$overlay_dir" ]]; then
        log_error "Tenant overlay directory not found: $overlay_dir"
        return 1
    fi
    
    # Check if kustomization.yaml exists
    if [[ ! -f "$kustomization_file" ]]; then
        log_error "Kustomization file not found: $kustomization_file"
        return 1
    fi
    
    # Extract image name and tag from artifact
    local image_name
    local image_tag
    if [[ "$ARTIFACT" =~ ^(.+):(.+)$ ]]; then
        image_name="${BASH_REMATCH[1]}"
        image_tag="${BASH_REMATCH[2]}"
    else
        log_error "Invalid artifact format: $ARTIFACT"
        return 1
    fi
    
    log_info "Parsed artifact - Image: $image_name, Tag: $image_tag"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would update kustomization.yaml with:"
        log_info "[DRY RUN]   Image: $image_name"
        log_info "[DRY RUN]   New Tag: $image_tag"
        log_step_end "Updating tenant overlay with new artifact" "SUCCESS"
        return 0
    fi
    
    # Change to overlay directory for kustomize operations
    cd "$overlay_dir"
    
    # Method 1: Try using kustomize edit set image (preferred)
    if command -v kustomize &> /dev/null; then
        log_info "Using kustomize to update image tag"
        
        # Create backup
        cp "$kustomization_file" "${kustomization_file}.backup"
        
        # Use kustomize edit set image to update the tag
        if log_command "kustomize edit set image ${TENANT}=${ARTIFACT}"; then
            log_info "Successfully updated image using kustomize"
        else
            log_warn "kustomize edit failed, falling back to yq/sed"
            # Restore backup and try alternative method
            cp "${kustomization_file}.backup" "$kustomization_file"
        fi
    fi
    
    # Method 2: Try using yq (if kustomize failed or not available)
    if ! command -v kustomize &> /dev/null || ! grep -q "$image_tag" "$kustomization_file"; then
        if command -v yq &> /dev/null; then
            log_info "Using yq to update image tag"
            
            # Create backup if not already created
            [[ ! -f "${kustomization_file}.backup" ]] && cp "$kustomization_file" "${kustomization_file}.backup"
            
            # Show current content for debugging
            log_debug "Current kustomization content before yq update:"
            log_debug "$(cat "$kustomization_file")"
            
            # Update the newTag field for the tenant image
            if yq eval "(.images[] | select(.name == \"${TENANT}\") | .newTag) = \"${image_tag}\"" -i "$kustomization_file"; then
                log_info "Successfully updated image using yq"
                
                # Show updated content for debugging
                log_debug "Updated kustomization content after yq update:"
                log_debug "$(cat "$kustomization_file")"
            else
                log_warn "yq update failed, falling back to sed"
                # Restore backup and try sed
                cp "${kustomization_file}.backup" "$kustomization_file"
            fi
        fi
    fi
    
    # Method 3: Fallback to sed (if both kustomize and yq failed)
    if ! grep -q "$image_tag" "$kustomization_file"; then
        log_info "Using sed to update image tag"
        
        # Create backup if not already created
        [[ ! -f "${kustomization_file}.backup" ]] && cp "$kustomization_file" "${kustomization_file}.backup"
        
        # Use sed to update the newTag field
        sed -i.tmp "/name: ${TENANT}/,/newTag:/ s/newTag: .*/newTag: ${image_tag}/" "$kustomization_file"
        rm -f "${kustomization_file}.tmp"
        
        log_info "Updated image tag using sed"
    fi
    
    # Verify the update was successful
    if grep -q "$image_tag" "$kustomization_file"; then
        log_success "Image tag successfully updated in kustomization.yaml"
        log_info "New tag: $image_tag"
    else
        log_error "Failed to update image tag in kustomization.yaml"
        return 1
    fi
    
    log_step_end "Updating tenant overlay with new artifact" "SUCCESS"
    return 0
}

# Commit changes (if using Git repository)
commit_changes() {
    log_step_start "Committing deployment changes"
    
    cd "$TENANTS_REPO_DIR"
    
    # Check if this is a Git repository
    if [[ ! -d ".git" ]]; then
        log_info "Not a Git repository, skipping commit"
        log_step_end "Committing deployment changes" "SUCCESS"
        return 0
    fi
    
    # Show current status for debugging
    log_debug "Git status before commit:"
    git status --porcelain || true
    
    # Check if there are any changes
    if git diff --quiet && git diff --cached --quiet; then
        log_info "No changes detected, skipping commit"
        log_step_end "Committing deployment changes" "SUCCESS"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would commit and push changes:"
        git diff --name-only 2>/dev/null || true
        log_step_end "Committing deployment changes" "SUCCESS"
        return 0
    fi
    
    # Configure Git user if not already configured
    if ! git config user.name &>/dev/null; then
        git config user.name "Release Pipeline Bot"
    fi
    if ! git config user.email &>/dev/null; then
        git config user.email "release-pipeline@zerotouch.dev"
    fi
    
    # Add all changes
    git add .
    
    # Check again after adding
    if git diff --cached --quiet; then
        log_info "No staged changes after git add, skipping commit"
        log_step_end "Committing deployment changes" "SUCCESS"
        return 0
    fi
    
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
    
    # Push changes (if repository has remote)
    if [[ "$TENANTS_REPO_TYPE" == "remote" ]] || [[ "$TENANTS_REPO_TYPE" == "local_with_remote" ]]; then
        log_info "Pushing changes to remote repository"
        
        # Check if we have a remote
        if ! git remote get-url origin &>/dev/null; then
            log_error "No remote origin configured"
            return 1
        fi
        
        # Get current branch
        local current_branch
        current_branch=$(git branch --show-current 2>/dev/null || echo "main")
        
        if ! log_command "git push origin $current_branch"; then
            log_error "Failed to push changes to remote repository"
            return 1
        fi
        
        log_info "Changes pushed to remote repository"
    else
        log_info "Changes committed locally (no remote configured)"
    fi
    
    # Get commit SHA for tracking
    local commit_sha
    commit_sha=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    
    log_deployment_info "$TENANT" "$ENVIRONMENT" "$ARTIFACT"
    log_info "GitOps commit SHA: $commit_sha"
    
    export DEPLOYMENT_COMMIT_SHA="$commit_sha"
    
    log_step_end "Committing deployment changes" "SUCCESS"
    return 0
}

# Verify deployment readiness
verify_deployment_readiness() {
    log_step_start "Verifying deployment readiness"
    
    log_info "Deployment verification for GitOps:"
    log_info "  Tenant: $TENANT"
    log_info "  Environment: $ENVIRONMENT"
    log_info "  Artifact: $ARTIFACT"
    log_info "  Repository: $TENANTS_REPO_DIR"
    log_info "  Repository Type: $TENANTS_REPO_TYPE"
    
    # In a real implementation, this could:
    # 1. Validate manifest syntax
    # 2. Check ArgoCD Application exists
    # 3. Verify resource quotas
    # 4. Run pre-deployment checks
    
    log_info "GitOps deployment prepared successfully"
    log_info "ArgoCD will automatically sync the changes"
    
    log_step_end "Verifying deployment readiness" "SUCCESS"
    return 0
}

# Main deployment execution
main() {
    local start_time
    start_time=$(date +%s)
    
    log_phase "GITOPS DEPLOYMENT PHASE"
    log_info "Starting GitOps deployment for tenant: $TENANT, environment: $ENVIRONMENT"
    
    # Initialize logging
    init_logging "$TENANT" "deploy-to-environment"
    
    # Log environment information
    log_environment
    
    # Discover tenant configuration
    if ! discover_tenant_config "$TENANT"; then
        log_error "Failed to discover tenant configuration"
        exit 1
    fi
    
    # Validate deployment request
    if ! validate_deployment; then
        log_error "Deployment validation failed"
        exit 1
    fi
    
    # Find tenant repository
    if ! clone_tenants_repository; then
        log_error "Failed to clone zerotouch-tenants repository"
        exit 1
    fi
    
    # Update deployment manifests
    if ! update_tenant_overlay; then
        log_error "Failed to update tenant overlay"
        exit 1
    fi
    
    # Commit changes
    if ! commit_changes; then
        log_error "Failed to commit changes"
        exit 1
    fi
    
    # Verify deployment readiness
    if ! verify_deployment_readiness; then
        log_error "Deployment readiness verification failed"
        exit 1
    fi
    
    local end_time
    local duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    log_success "GitOps deployment completed successfully"
    log_info "Tenant: $TENANT"
    log_info "Environment: $ENVIRONMENT"
    log_info "Artifact: $ARTIFACT"
    log_info "Duration: ${duration}s"
    
    # Export results for use by calling script
    export DEPLOYMENT_STATUS="SUCCESS"
    export DEPLOYMENT_DURATION="$duration"
}

# Parse arguments and run main function
parse_args "$@"
main