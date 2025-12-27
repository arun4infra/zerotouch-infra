#!/bin/bash
# logging.sh - Enhanced logging utilities for release pipeline

# Get the directory of this script (lib directory)
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common utilities from the same lib directory
if [[ ! -f "${LIB_DIR}/common.sh" ]]; then
    echo "Error: common.sh not found at ${LIB_DIR}/common.sh" >&2
    exit 1
fi
source "${LIB_DIR}/common.sh"

# Log directory
LOG_DIR="${HOME}/.cache/zerotouch-platform/logs"

# Current log file
CURRENT_LOG_FILE=""

# Initialize logging
init_logging() {
    local tenant="${1:-unknown}"
    local operation="${2:-pipeline}"
    
    mkdir -p "$LOG_DIR"
    
    local timestamp
    timestamp=$(get_timestamp_filename)
    CURRENT_LOG_FILE="${LOG_DIR}/${tenant}-${operation}-${timestamp}.log"
    
    # Create log file with header
    cat > "$CURRENT_LOG_FILE" << EOF
# Release Pipeline Log
# Tenant: $tenant
# Operation: $operation
# Started: $(get_timestamp)
# Host: $(hostname)
# User: $(whoami)
# Working Directory: $(pwd)

EOF
    
    log_info "Logging initialized: $CURRENT_LOG_FILE"
}

# Log to both console and file
log_to_file() {
    local level="$1"
    local message="$2"
    
    if [[ -n "$CURRENT_LOG_FILE" ]]; then
        echo "[$level] $(get_timestamp) $message" >> "$CURRENT_LOG_FILE"
    fi
}

# Enhanced logging functions that also write to file
log_error_enhanced() {
    local message="$*"
    log_error "$message"
    log_to_file "ERROR" "$message"
}

log_warn_enhanced() {
    local message="$*"
    log_warn "$message"
    log_to_file "WARN" "$message"
}

log_info_enhanced() {
    local message="$*"
    log_info "$message"
    log_to_file "INFO" "$message"
}

log_debug_enhanced() {
    local message="$*"
    log_debug "$message"
    log_to_file "DEBUG" "$message"
}

# Log command execution with output capture
log_command() {
    local cmd="$*"
    local output
    local exit_code
    
    log_info_enhanced "Executing: $cmd"
    
    # Capture both stdout and stderr
    output=$(eval "$cmd" 2>&1)
    exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log_debug_enhanced "Command succeeded: $cmd"
        if [[ -n "$output" ]]; then
            log_debug_enhanced "Output: $output"
        fi
    else
        log_error_enhanced "Command failed (exit code: $exit_code): $cmd"
        if [[ -n "$output" ]]; then
            log_error_enhanced "Output: $output"
        fi
    fi
    
    return $exit_code
}

# Log step start/end
log_step_start() {
    local step="$1"
    local separator="=================================================="
    
    log_info_enhanced "$separator"
    log_info_enhanced "STEP: $step"
    log_info_enhanced "$separator"
}

log_step_end() {
    local step="$1"
    local status="${2:-SUCCESS}"
    local separator="=================================================="
    
    if [[ "$status" == "SUCCESS" ]]; then
        log_success "STEP COMPLETED: $step"
    else
        log_failure "STEP FAILED: $step"
    fi
    
    log_info_enhanced "$separator"
    log_to_file "STEP_END" "$step - $status"
}

# Log pipeline phase
log_phase() {
    local phase="$1"
    local separator="##################################################"
    
    log_info_enhanced ""
    log_info_enhanced "$separator"
    log_info_enhanced "PHASE: $phase"
    log_info_enhanced "$separator"
    log_info_enhanced ""
}

# Log environment information
log_environment() {
    log_info_enhanced "Environment Information:"
    log_info_enhanced "  Hostname: $(hostname)"
    log_info_enhanced "  User: $(whoami)"
    log_info_enhanced "  Working Directory: $(pwd)"
    log_info_enhanced "  Shell: $SHELL"
    log_info_enhanced "  PATH: $PATH"
    
    if is_github_actions; then
        log_info_enhanced "  GitHub Actions: true"
        log_info_enhanced "  Runner OS: ${RUNNER_OS:-unknown}"
        log_info_enhanced "  Workflow: ${GITHUB_WORKFLOW:-unknown}"
        log_info_enhanced "  Run ID: ${GITHUB_RUN_ID:-unknown}"
    else
        log_info_enhanced "  GitHub Actions: false"
    fi
    
    if is_preview_mode; then
        log_info_enhanced "  Execution Mode: preview"
    else
        log_info_enhanced "  Execution Mode: production"
    fi
}

# Log configuration summary
log_config_summary() {
    local tenant="$1"
    
    log_info_enhanced "Configuration Summary for tenant: $tenant"
    log_info_enhanced "  Service Name: $(get_tenant_config name)"
    log_info_enhanced "  Namespace: $(get_tenant_config namespace)"
    log_info_enhanced "  Dockerfile: $(get_tenant_config dockerfile)"
    log_info_enhanced "  Build Context: $(get_tenant_config build_context)"
    log_info_enhanced "  Release Enabled: $(get_tenant_config release_enabled)"
    
    if is_release_enabled; then
        log_info_enhanced "  Registry: $(get_tenant_release_config registry)"
        log_info_enhanced "  Environments: $(get_tenant_release_config environments)"
        log_info_enhanced "  Validation Mode: $(get_tenant_release_config validation_mode)"
        log_info_enhanced "  Dev to Staging: $(get_tenant_release_config dev_to_staging)"
        log_info_enhanced "  Staging to Production: $(get_tenant_release_config staging_to_production)"
    fi
}

# Log artifact information
log_artifact_info() {
    local artifact_id="$1"
    local registry="$2"
    local tag="$3"
    
    log_info_enhanced "Artifact Information:"
    log_info_enhanced "  Artifact ID: $artifact_id"
    log_info_enhanced "  Registry: $registry"
    log_info_enhanced "  Tag: $tag"
    log_info_enhanced "  Full Image: ${registry}/${artifact_id}:${tag}"
}

# Log deployment information
log_deployment_info() {
    local tenant="$1"
    local environment="$2"
    local artifact="$3"
    
    log_info_enhanced "Deployment Information:"
    log_info_enhanced "  Tenant: $tenant"
    log_info_enhanced "  Environment: $environment"
    log_info_enhanced "  Artifact: $artifact"
    log_info_enhanced "  Timestamp: $(get_timestamp)"
}

# Log promotion gate information
log_promotion_gate_info() {
    local tenant="$1"
    local source_env="$2"
    local target_env="$3"
    local artifact="$4"
    local gate_id="$5"
    
    log_info_enhanced "Promotion Gate Information:"
    log_info_enhanced "  Tenant: $tenant"
    log_info_enhanced "  Source Environment: $source_env"
    log_info_enhanced "  Target Environment: $target_env"
    log_info_enhanced "  Artifact: $artifact"
    log_info_enhanced "  Gate ID: $gate_id"
    log_info_enhanced "  Created: $(get_timestamp)"
}

# Log pipeline summary
log_pipeline_summary() {
    local tenant="$1"
    local trigger="$2"
    local status="$3"
    local duration="$4"
    
    local separator="##################################################"
    
    log_info_enhanced ""
    log_info_enhanced "$separator"
    log_info_enhanced "PIPELINE SUMMARY"
    log_info_enhanced "$separator"
    log_info_enhanced "  Tenant: $tenant"
    log_info_enhanced "  Trigger: $trigger"
    log_info_enhanced "  Status: $status"
    log_info_enhanced "  Duration: $duration"
    log_info_enhanced "  Log File: $CURRENT_LOG_FILE"
    log_info_enhanced "  Completed: $(get_timestamp)"
    log_info_enhanced "$separator"
    log_info_enhanced ""
}

# Get current log file path
get_current_log_file() {
    echo "$CURRENT_LOG_FILE"
}

# Archive old log files
archive_old_logs() {
    local retention_days="${1:-7}"
    
    if [[ -d "$LOG_DIR" ]]; then
        log_debug "Archiving log files older than $retention_days days"
        find "$LOG_DIR" -name "*.log" -type f -mtime +$retention_days -delete
    fi
}

# Export enhanced logging functions
export -f init_logging log_to_file
export -f log_error_enhanced log_warn_enhanced log_info_enhanced log_debug_enhanced
export -f log_command log_step_start log_step_end log_phase
export -f log_environment log_config_summary log_artifact_info
export -f log_deployment_info log_promotion_gate_info log_pipeline_summary
export -f get_current_log_file archive_old_logs

# Override standard logging functions with enhanced versions
alias log_error='log_error_enhanced'
alias log_warn='log_warn_enhanced'
alias log_info='log_info_enhanced'
alias log_debug='log_debug_enhanced'