#!/bin/bash
# common.sh - Common utilities for release pipeline scripts

# Color codes for output (only set if not already defined)
if [[ -z "${RED:-}" ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly NC='\033[0m' # No Color
fi

# Log levels (only set if not already defined)
if [[ -z "${LOG_LEVEL_ERROR:-}" ]]; then
    readonly LOG_LEVEL_ERROR=1
    readonly LOG_LEVEL_WARN=2
    readonly LOG_LEVEL_INFO=3
    readonly LOG_LEVEL_DEBUG=4
fi

# Default log level
LOG_LEVEL="${LOG_LEVEL:-info}"

# Convert log level string to number
get_log_level_num() {
    local level_lower
    level_lower=$(echo "${LOG_LEVEL:-info}" | tr '[:upper:]' '[:lower:]')
    case "$level_lower" in
        "error") echo $LOG_LEVEL_ERROR ;;
        "warn"|"warning") echo $LOG_LEVEL_WARN ;;
        "info") echo $LOG_LEVEL_INFO ;;
        "debug") echo $LOG_LEVEL_DEBUG ;;
        *) echo $LOG_LEVEL_INFO ;;
    esac
}

# Logging functions
log_error() {
    local current_level=$(get_log_level_num)
    if [[ $current_level -ge $LOG_LEVEL_ERROR ]]; then
        echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
    fi
}

log_warn() {
    local current_level=$(get_log_level_num)
    if [[ $current_level -ge $LOG_LEVEL_WARN ]]; then
        echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*" >&2
    fi
}

log_info() {
    local current_level=$(get_log_level_num)
    if [[ $current_level -ge $LOG_LEVEL_INFO ]]; then
        echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*"
    fi
}

log_debug() {
    local current_level=$(get_log_level_num)
    if [[ $current_level -ge $LOG_LEVEL_DEBUG ]]; then
        echo -e "${GREEN}[DEBUG]${NC} $(date '+%Y-%m-%d %H:%M:%S') $*"
    fi
}

# Success/failure indicators
log_success() {
    echo -e "${GREEN}✅${NC} $*"
}

log_failure() {
    echo -e "${RED}❌${NC} $*" >&2
}

# Utility functions
check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Required command not found: $cmd"
        return 1
    fi
    return 0
}

check_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        log_error "Required file not found: $file"
        return 1
    fi
    return 0
}

check_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        log_error "Required directory not found: $dir"
        return 1
    fi
    return 0
}

# Execute command with logging
execute_with_logging() {
    local cmd="$*"
    log_debug "Executing: $cmd"
    
    if [[ $(get_log_level_num) -ge $LOG_LEVEL_DEBUG ]]; then
        # Show output in debug mode
        eval "$cmd"
    else
        # Hide output in normal mode
        eval "$cmd" &> /dev/null
    fi
}

# Retry function with exponential backoff
retry_with_backoff() {
    local max_attempts="$1"
    local delay="$2"
    local cmd="${*:3}"
    
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Attempt $attempt/$max_attempts: $cmd"
        
        if eval "$cmd"; then
            return 0
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            log_warn "Command failed, retrying in ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))  # Exponential backoff
        fi
        
        ((attempt++))
    done
    
    log_error "Command failed after $max_attempts attempts: $cmd"
    return 1
}

# Generate unique identifier
generate_id() {
    local prefix="${1:-pipeline}"
    echo "${prefix}-$(date +%Y%m%d-%H%M%S)-$(openssl rand -hex 4)"
}

# Get current timestamp
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S UTC'
}

# Get current timestamp for filenames
get_timestamp_filename() {
    date '+%Y%m%d-%H%M%S'
}

# Validate tenant name format
validate_tenant_name() {
    local tenant="$1"
    
    # Check if tenant name matches expected pattern (lowercase, hyphens allowed)
    if [[ ! "$tenant" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]]; then
        log_error "Invalid tenant name format: $tenant"
        log_error "Tenant names must start with a letter, contain only lowercase letters, numbers, and hyphens, and end with a letter or number"
        return 1
    fi
    
    return 0
}

# Validate environment name
validate_environment_name() {
    local env="$1"
    local valid_envs=("dev" "staging" "production")
    
    for valid_env in "${valid_envs[@]}"; do
        if [[ "$env" == "$valid_env" ]]; then
            return 0
        fi
    done
    
    log_error "Invalid environment name: $env"
    log_error "Valid environments: ${valid_envs[*]}"
    return 1
}

# Check if running in GitHub Actions
is_github_actions() {
    [[ "${GITHUB_ACTIONS:-}" == "true" ]]
}

# Check if running in preview mode
is_preview_mode() {
    [[ "${EXECUTION_MODE:-}" == "preview" ]] || is_github_actions
}

# Get platform root directory
get_platform_root() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cd "${script_dir}/../../.." && pwd
}

# Get tenant repository root (when running in tenant context)
get_tenant_root() {
    # In GitHub Actions, this would be the workspace
    if is_github_actions; then
        echo "${GITHUB_WORKSPACE:-$(pwd)}"
    else
        # For local testing, try to find the tenant directory intelligently
        local current_dir="$(pwd)"
        local tenant_name="${TENANT:-}"
        
        # If we're already in a tenant directory, use it
        if [[ -f "ci/config.yaml" ]]; then
            echo "$current_dir"
            return 0
        fi
        
        # If TENANT is set, try to find it relative to platform root
        if [[ -n "$tenant_name" ]]; then
            local platform_root
            platform_root=$(get_platform_root)
            local workspace_root
            workspace_root=$(cd "${platform_root}/.." && pwd)
            local tenant_dir="${workspace_root}/${tenant_name}"
            
            if [[ -d "$tenant_dir" && -f "${tenant_dir}/ci/config.yaml" ]]; then
                echo "$tenant_dir"
                return 0
            fi
        fi
        
        # Fallback to current directory
        echo "$current_dir"
    fi
}

# Export functions for use in other scripts
export -f log_error log_warn log_info log_debug log_success log_failure
export -f check_command check_file check_directory
export -f execute_with_logging retry_with_backoff
export -f generate_id get_timestamp get_timestamp_filename
export -f validate_tenant_name validate_environment_name
export -f is_github_actions is_preview_mode
export -f get_platform_root get_tenant_root