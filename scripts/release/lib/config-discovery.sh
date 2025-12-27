#!/bin/bash
# config-discovery.sh - Configuration discovery from zerotouch-tenants repository

# Get the directory of this script (lib directory)
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common utilities from the same lib directory
if [[ ! -f "${LIB_DIR}/common.sh" ]]; then
    echo "Error: common.sh not found at ${LIB_DIR}/common.sh" >&2
    exit 1
fi
source "${LIB_DIR}/common.sh"

# Configuration cache directory
CONFIG_CACHE_DIR="${HOME}/.cache/zerotouch-platform/config"

# Tenant configuration structure (using simple variables instead of associative arrays)
TENANT_CONFIG_NAME=""
TENANT_CONFIG_NAMESPACE=""
TENANT_CONFIG_DOCKERFILE=""
TENANT_CONFIG_BUILD_CONTEXT=""
TENANT_CONFIG_RELEASE_ENABLED=""
TENANT_CONFIG_RELEASE_CONFIG_FILE=""

TENANT_RELEASE_CONFIG_ENVIRONMENTS=""
TENANT_RELEASE_CONFIG_DEV_TO_STAGING=""
TENANT_RELEASE_CONFIG_STAGING_TO_PRODUCTION=""
TENANT_RELEASE_CONFIG_REGISTRY=""
TENANT_RELEASE_CONFIG_RETENTION_DAYS=""
TENANT_RELEASE_CONFIG_VALIDATION_MODE=""
TENANT_RELEASE_CONFIG_BOOTSTRAP_MODE=""

# Initialize configuration cache
init_config_cache() {
    mkdir -p "$CONFIG_CACHE_DIR"
    log_debug "Configuration cache initialized: $CONFIG_CACHE_DIR"
}

# Discover tenant configuration from zerotouch-tenants repository
discover_tenant_config() {
    local tenant="$1"
    
    if [[ -z "$tenant" ]]; then
        log_error "Tenant name is required for configuration discovery"
        return 1
    fi
    
    log_info "Discovering configuration for tenant: $tenant"
    
    # Validate tenant name format
    if ! validate_tenant_name "$tenant"; then
        return 1
    fi
    
    # Initialize cache
    init_config_cache
    
    # Discover tenant CI configuration
    if ! discover_tenant_ci_config "$tenant"; then
        log_error "Failed to discover tenant CI configuration"
        return 1
    fi
    
    # Discover tenant release configuration
    if ! discover_tenant_release_config "$tenant"; then
        log_error "Failed to discover tenant release configuration"
        return 1
    fi
    
    # Discover tenant repository configuration from zerotouch-tenants
    if ! discover_tenant_repo_config "$tenant"; then
        log_error "Failed to discover tenant repository configuration"
        return 1
    fi
    
    log_success "Configuration discovery completed for tenant: $tenant"
    return 0
}

# Discover tenant CI configuration (from tenant repository)
discover_tenant_ci_config() {
    local tenant="$1"
    local tenant_root
    tenant_root=$(get_tenant_root)
    
    log_debug "Discovering CI configuration for tenant: $tenant"
    
    # Check for ci/config.yaml in tenant repository
    local ci_config_file="${tenant_root}/ci/config.yaml"
    if [[ ! -f "$ci_config_file" ]]; then
        log_error "Tenant CI configuration not found: $ci_config_file"
        return 1
    fi
    
    # Parse CI configuration
    log_debug "Parsing CI configuration: $ci_config_file"
    
    # Extract key configuration values using yq or basic parsing
    if command -v yq &> /dev/null; then
        TENANT_CONFIG_NAME=$(yq eval '.service.name' "$ci_config_file")
        TENANT_CONFIG_NAMESPACE=$(yq eval '.service.namespace' "$ci_config_file")
        TENANT_CONFIG_DOCKERFILE=$(yq eval '.build.dockerfile' "$ci_config_file")
        TENANT_CONFIG_BUILD_CONTEXT=$(yq eval '.build.context' "$ci_config_file")
        TENANT_CONFIG_RELEASE_ENABLED=$(yq eval '.release.enabled' "$ci_config_file")
        TENANT_CONFIG_RELEASE_CONFIG_FILE=$(yq eval '.release.config_file' "$ci_config_file")
    else
        # Fallback to basic grep parsing
        TENANT_CONFIG_NAME=$(grep -E '^\s*name:' "$ci_config_file" | sed 's/.*name:\s*["\x27]\?\([^"\x27]*\)["\x27]\?.*/\1/')
        TENANT_CONFIG_NAMESPACE=$(grep -E '^\s*namespace:' "$ci_config_file" | sed 's/.*namespace:\s*["\x27]\?\([^"\x27]*\)["\x27]\?.*/\1/')
        TENANT_CONFIG_DOCKERFILE=$(grep -E '^\s*dockerfile:' "$ci_config_file" | sed 's/.*dockerfile:\s*["\x27]\?\([^"\x27]*\)["\x27]\?.*/\1/')
        TENANT_CONFIG_BUILD_CONTEXT=$(grep -E '^\s*context:' "$ci_config_file" | sed 's/.*context:\s*["\x27]\?\([^"\x27]*\)["\x27]\?.*/\1/')
        TENANT_CONFIG_RELEASE_ENABLED=$(grep -E '^\s*enabled:' "$ci_config_file" | sed 's/.*enabled:\s*\([^#]*\).*/\1/' | tr -d ' ')
        TENANT_CONFIG_RELEASE_CONFIG_FILE=$(grep -E '^\s*config_file:' "$ci_config_file" | sed 's/.*config_file:\s*["\x27]\?\([^"\x27]*\)["\x27]\?.*/\1/')
    fi
    
    # Validate required fields
    if [[ -z "$TENANT_CONFIG_NAME" || "$TENANT_CONFIG_NAME" == "null" ]]; then
        log_error "Service name not found in CI configuration"
        return 1
    fi
    
    if [[ -z "$TENANT_CONFIG_NAMESPACE" || "$TENANT_CONFIG_NAMESPACE" == "null" ]]; then
        log_error "Service namespace not found in CI configuration"
        return 1
    fi
    
    log_debug "CI configuration parsed successfully"
    log_debug "  Service name: $TENANT_CONFIG_NAME"
    log_debug "  Namespace: $TENANT_CONFIG_NAMESPACE"
    log_debug "  Release enabled: $TENANT_CONFIG_RELEASE_ENABLED"
    
    return 0
}

# Discover tenant release configuration
discover_tenant_release_config() {
    local tenant="$1"
    local tenant_root
    tenant_root=$(get_tenant_root)
    
    log_debug "Discovering release configuration for tenant: $tenant"
    
    # Check if release is enabled
    if [[ "$TENANT_CONFIG_RELEASE_ENABLED" != "true" ]]; then
        log_warn "Release pipeline is not enabled for tenant: $tenant"
        return 0
    fi
    
    # Get release config file path
    local release_config_file="${tenant_root}/${TENANT_CONFIG_RELEASE_CONFIG_FILE}"
    if [[ -z "$TENANT_CONFIG_RELEASE_CONFIG_FILE" || ! -f "$release_config_file" ]]; then
        log_error "Release configuration file not found: $release_config_file"
        return 1
    fi
    
    log_debug "Parsing release configuration: $release_config_file"
    
    # Parse release configuration
    if command -v yq &> /dev/null; then
        TENANT_RELEASE_CONFIG_ENVIRONMENTS=$(yq eval '.release.environments | join(",")' "$release_config_file")
        TENANT_RELEASE_CONFIG_DEV_TO_STAGING=$(yq eval '.release.promotion.dev_to_staging' "$release_config_file")
        TENANT_RELEASE_CONFIG_STAGING_TO_PRODUCTION=$(yq eval '.release.promotion.staging_to_production' "$release_config_file")
        TENANT_RELEASE_CONFIG_REGISTRY=$(yq eval '.release.artifacts.registry' "$release_config_file")
        TENANT_RELEASE_CONFIG_RETENTION_DAYS=$(yq eval '.release.artifacts.retention_days' "$release_config_file")
        TENANT_RELEASE_CONFIG_VALIDATION_MODE=$(yq eval '.release.testing.validation_mode' "$release_config_file")
        TENANT_RELEASE_CONFIG_BOOTSTRAP_MODE=$(yq eval '.release.testing.bootstrap_mode' "$release_config_file")
    else
        # Fallback parsing for environments (simplified)
        TENANT_RELEASE_CONFIG_ENVIRONMENTS="dev,staging,production"
        TENANT_RELEASE_CONFIG_DEV_TO_STAGING="manual"
        TENANT_RELEASE_CONFIG_STAGING_TO_PRODUCTION="manual"
        TENANT_RELEASE_CONFIG_REGISTRY="ghcr.io"
        TENANT_RELEASE_CONFIG_RETENTION_DAYS="30"
        TENANT_RELEASE_CONFIG_VALIDATION_MODE="preview"
        TENANT_RELEASE_CONFIG_BOOTSTRAP_MODE="preview"
    fi
    
    log_debug "Release configuration parsed successfully"
    log_debug "  Environments: $TENANT_RELEASE_CONFIG_ENVIRONMENTS"
    log_debug "  Registry: $TENANT_RELEASE_CONFIG_REGISTRY"
    log_debug "  Validation mode: $TENANT_RELEASE_CONFIG_VALIDATION_MODE"
    
    return 0
}

# Discover tenant repository configuration from zerotouch-tenants
discover_tenant_repo_config() {
    local tenant="$1"
    
    log_debug "Discovering tenant repository configuration for: $tenant"
    
    # In a real implementation, this would fetch from zerotouch-tenants repository
    # For now, we'll use the existing tenant cache or create minimal config
    
    local tenant_cache_dir="${CONFIG_CACHE_DIR}/${tenant}"
    mkdir -p "$tenant_cache_dir"
    
    # Create or update tenant repository configuration
    local tenant_repo_config="${tenant_cache_dir}/repo-config.yaml"
    cat > "$tenant_repo_config" << EOF
tenant: ${tenant}
repoURL: https://github.com/org/${tenant}
targetRevision: main
appPath: platform/claims
namespace: ${TENANT_CONFIG_NAMESPACE}

release:
  environments:
    - dev
    - staging
    - production
  promotion:
    dev_to_staging: manual
    staging_to_production: manual
  artifacts:
    registry: ${TENANT_RELEASE_CONFIG_REGISTRY:-ghcr.io}
    retention_days: ${TENANT_RELEASE_CONFIG_RETENTION_DAYS:-30}
  testing:
    validation_mode: ${TENANT_RELEASE_CONFIG_VALIDATION_MODE:-preview}
    bootstrap_mode: ${TENANT_RELEASE_CONFIG_BOOTSTRAP_MODE:-preview}
EOF
    
    log_debug "Tenant repository configuration created: $tenant_repo_config"
    return 0
}

# Validate tenant configuration
validate_tenant_config() {
    local tenant="$1"
    
    log_info "Validating configuration for tenant: $tenant"
    
    # Validate required CI configuration
    local required_ci_fields=("name" "namespace" "dockerfile" "build_context")
    for field in "${required_ci_fields[@]}"; do
        local var_name="TENANT_CONFIG_$(echo "$field" | tr '[:lower:]' '[:upper:]')"
        local var_value
        case "$field" in
            "name") var_value="$TENANT_CONFIG_NAME" ;;
            "namespace") var_value="$TENANT_CONFIG_NAMESPACE" ;;
            "dockerfile") var_value="$TENANT_CONFIG_DOCKERFILE" ;;
            "build_context") var_value="$TENANT_CONFIG_BUILD_CONTEXT" ;;
        esac
        if [[ -z "$var_value" || "$var_value" == "null" ]]; then
            log_error "Required CI configuration field missing: $field"
            return 1
        fi
    done
    
    # Validate service name matches tenant
    if [[ "$TENANT_CONFIG_NAME" != "$tenant" ]]; then
        log_error "Service name mismatch: expected '$tenant', got '$TENANT_CONFIG_NAME'"
        return 1
    fi
    
    # Validate release configuration if enabled
    if [[ "$TENANT_CONFIG_RELEASE_ENABLED" == "true" ]]; then
        local required_release_fields=("environments" "registry" "validation_mode")
        for field in "${required_release_fields[@]}"; do
            local var_value
            case "$field" in
                "environments") var_value="$TENANT_RELEASE_CONFIG_ENVIRONMENTS" ;;
                "registry") var_value="$TENANT_RELEASE_CONFIG_REGISTRY" ;;
                "validation_mode") var_value="$TENANT_RELEASE_CONFIG_VALIDATION_MODE" ;;
            esac
            if [[ -z "$var_value" || "$var_value" == "null" ]]; then
                log_error "Required release configuration field missing: $field"
                return 1
            fi
        done
        
        # Validate environments
        IFS=',' read -ra envs <<< "$TENANT_RELEASE_CONFIG_ENVIRONMENTS"
        for env in "${envs[@]}"; do
            if ! validate_environment_name "$env"; then
                return 1
            fi
        done
        
        # Validate validation mode
        if [[ "$TENANT_RELEASE_CONFIG_VALIDATION_MODE" != "preview" ]]; then
            log_error "Invalid validation mode: $TENANT_RELEASE_CONFIG_VALIDATION_MODE (must be 'preview')"
            return 1
        fi
    fi
    
    log_success "Configuration validation completed for tenant: $tenant"
    return 0
}

# Get tenant configuration value
get_tenant_config() {
    local key="$1"
    case "$key" in
        "name") echo "$TENANT_CONFIG_NAME" ;;
        "namespace") echo "$TENANT_CONFIG_NAMESPACE" ;;
        "dockerfile") echo "$TENANT_CONFIG_DOCKERFILE" ;;
        "build_context") echo "$TENANT_CONFIG_BUILD_CONTEXT" ;;
        "release_enabled") echo "$TENANT_CONFIG_RELEASE_ENABLED" ;;
        "release_config_file") echo "$TENANT_CONFIG_RELEASE_CONFIG_FILE" ;;
        *) echo "" ;;
    esac
}

# Get tenant release configuration value
get_tenant_release_config() {
    local key="$1"
    case "$key" in
        "environments") echo "$TENANT_RELEASE_CONFIG_ENVIRONMENTS" ;;
        "dev_to_staging") echo "$TENANT_RELEASE_CONFIG_DEV_TO_STAGING" ;;
        "staging_to_production") echo "$TENANT_RELEASE_CONFIG_STAGING_TO_PRODUCTION" ;;
        "registry") echo "$TENANT_RELEASE_CONFIG_REGISTRY" ;;
        "retention_days") echo "$TENANT_RELEASE_CONFIG_RETENTION_DAYS" ;;
        "validation_mode") echo "$TENANT_RELEASE_CONFIG_VALIDATION_MODE" ;;
        "bootstrap_mode") echo "$TENANT_RELEASE_CONFIG_BOOTSTRAP_MODE" ;;
        *) echo "" ;;
    esac
}

# Get tenant environments as array
get_tenant_environments() {
    local envs_string="${TENANT_RELEASE_CONFIG_ENVIRONMENTS:-dev,staging,production}"
    IFS=',' read -ra envs <<< "$envs_string"
    printf '%s\n' "${envs[@]}"
}

# Check if tenant has release pipeline enabled
is_release_enabled() {
    [[ "$TENANT_CONFIG_RELEASE_ENABLED" == "true" ]]
}

# Export functions for use in other scripts
export -f discover_tenant_config validate_tenant_config
export -f get_tenant_config get_tenant_release_config get_tenant_environments
export -f is_release_enabled