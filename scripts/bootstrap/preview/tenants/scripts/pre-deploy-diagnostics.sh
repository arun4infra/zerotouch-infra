#!/bin/bash
set -euo pipefail

# ==============================================================================
# Pre-Deploy Diagnostics Script
# ==============================================================================
# Purpose: Run pre-deployment diagnostics based on service config
# Usage: ./pre-deploy-diagnostics.sh
# ==============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[PRE-DEPLOY]${NC} $*"; }
log_success() { echo -e "${GREEN}[PRE-DEPLOY]${NC} $*"; }
log_error() { echo -e "${RED}[PRE-DEPLOY]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[PRE-DEPLOY]${NC} $*"; }

# Helper function to check if a config flag is enabled
config_enabled() {
    local config_path="$1"
    if command -v yq &> /dev/null; then
        local value=$(yq eval ".$config_path // false" ci/config.yaml 2>/dev/null)
        [[ "$value" == "true" ]]
    else
        # Fallback: assume enabled if not specified
        return 0
    fi
}

# Check platform APIs if enabled
check_platform_apis() {
    log_info "Checking required platform APIs..."
    
    local required_xrds=(
        "xeventdrivenservices.platform.bizmatters.io"
        "xpostgresinstances.database.bizmatters.io"
        "xdragonflyinstances.database.bizmatters.io"
    )
    
    for xrd in "${required_xrds[@]}"; do
        if kubectl get xrd "$xrd" >/dev/null 2>&1; then
            log_success "✓ XRD $xrd exists"
        else
            log_error "✗ XRD $xrd not found"
            exit 1
        fi
    done
}

# Main execution
main() {
    log_info "Running pre-deploy diagnostics based on config flags"
    
    # Check platform APIs if enabled
    if config_enabled "diagnostics.pre_deploy.check_platform_apis"; then
        log_info "Checking platform APIs..."
        check_platform_apis
    else
        log_info "Platform API checks disabled in config"
    fi
    
    log_success "Pre-deploy diagnostics completed successfully"
}

main "$@"