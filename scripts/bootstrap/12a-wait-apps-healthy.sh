#!/bin/bash
# Wait for All Applications to be Synced & Healthy
# Usage: ./13-wait-apps-healthy.sh [--timeout <seconds>]
#
# This script waits for all ArgoCD applications to reach Synced & Healthy status.
# Only Synced & Healthy is considered success - Progressing is NOT accepted.

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
TIMEOUT=600  # 10 minutes default
POLL_INTERVAL=15
PREVIEW_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --preview-mode)
            PREVIEW_MODE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Infrastructure apps that can be unhealthy in preview mode
# These are known to have issues in Kind clusters but don't affect core functionality
PREVIEW_OPTIONAL_APPS=(
    "cilium"                    # Kind uses kindnet instead
    "argocd-repo-credentials"   # Tenant repo credentials fail without SSM params
)

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Waiting for All Applications to be Healthy                ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Timeout: $((TIMEOUT/60)) minutes${NC}"
echo ""

ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    # Get all applications
    APPS_JSON=$(kubectl get applications -n argocd -o json 2>/dev/null)
    TOTAL_APPS=$(echo "$APPS_JSON" | jq -r '.items | length')
    
    if [ "$TOTAL_APPS" -eq 0 ]; then
        echo -e "${YELLOW}⚠️  No applications found yet, waiting...${NC}"
        sleep $POLL_INTERVAL
        ELAPSED=$((ELAPSED + POLL_INTERVAL))
        continue
    fi
    
    # Count healthy apps
    HEALTHY_APPS=0
    NOT_READY_APPS=()
    OPTIONAL_UNHEALTHY=0
    
    while IFS='|' read -r name sync health; do
        if [[ "$sync" == "Synced" && "$health" == "Healthy" ]]; then
            HEALTHY_APPS=$((HEALTHY_APPS + 1))
        else
            # Check if this is an optional app in preview mode
            IS_OPTIONAL=false
            if [ "$PREVIEW_MODE" = true ]; then
                for optional_app in "${PREVIEW_OPTIONAL_APPS[@]}"; do
                    if [ "$name" = "$optional_app" ]; then
                        IS_OPTIONAL=true
                        OPTIONAL_UNHEALTHY=$((OPTIONAL_UNHEALTHY + 1))
                        break
                    fi
                done
            fi
            
            if [ "$IS_OPTIONAL" = false ]; then
                NOT_READY_APPS+=("$name:$sync/$health")
            fi
        fi
    done < <(echo "$APPS_JSON" | jq -r '.items[] | "\(.metadata.name)|\(.status.sync.status // "Unknown")|\(.status.health.status // "Unknown")"')
    
    # Check if all required apps are healthy
    REQUIRED_APPS=$((TOTAL_APPS - OPTIONAL_UNHEALTHY))
    if [ $HEALTHY_APPS -eq $REQUIRED_APPS ]; then
        echo ""
        if [ "$PREVIEW_MODE" = true ] && [ $OPTIONAL_UNHEALTHY -gt 0 ]; then
            echo -e "${GREEN}✓ All $HEALTHY_APPS required applications are Synced & Healthy${NC}"
            echo -e "${BLUE}ℹ  $OPTIONAL_UNHEALTHY optional infrastructure apps are unhealthy (acceptable in preview mode)${NC}"
        else
            echo -e "${GREEN}✓ All $TOTAL_APPS applications are Synced & Healthy${NC}"
        fi
        echo ""
        exit 0
    fi
    
    # Print progress
    echo -e "${YELLOW}⏳ $HEALTHY_APPS/$TOTAL_APPS healthy ($((ELAPSED/60))m $((ELAPSED%60))s elapsed)${NC}"
    
    # Show not ready apps with error details
    if [ ${#NOT_READY_APPS[@]} -gt 0 ]; then
        echo -e "   ${YELLOW}Not ready applications:${NC}"
        for app_status in "${NOT_READY_APPS[@]:0:5}"; do
            app_name=$(echo "$app_status" | cut -d':' -f1)
            status=$(echo "$app_status" | cut -d':' -f2)
            
            # Get error message if available
            error_msg=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.conditions[?(@.type=="SyncError")].message}' 2>/dev/null)
            health_msg=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.conditions[?(@.type=="HealthError")].message}' 2>/dev/null)
            
            echo -n "     - $app_name: $status"
            
            if [ -n "$error_msg" ]; then
                echo -e " ${RED}(Sync: ${error_msg:0:80})${NC}"
            elif [ -n "$health_msg" ]; then
                echo -e " ${RED}(Health: ${health_msg:0:80})${NC}"
            else
                echo ""
            fi
        done
        
        if [ ${#NOT_READY_APPS[@]} -gt 5 ]; then
            echo -e "     ${YELLOW}... and $((${#NOT_READY_APPS[@]} - 5)) more${NC}"
        fi
    fi
    
    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

# Timeout - print detailed failure info
echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║   TIMEOUT: Applications not healthy after $((TIMEOUT/60)) minutes        ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Get final status
APPS_JSON=$(kubectl get applications -n argocd -o json 2>/dev/null)

echo -e "${YELLOW}Application Status:${NC}"
echo ""

while IFS='|' read -r name sync health; do
    if [[ "$sync" == "Synced" && "$health" == "Healthy" ]]; then
        echo -e "  ✅ $name: $sync / $health"
    else
        echo -e "  ❌ $name: $sync / $health"
        
        # Print conditions/errors for failed apps
        CONDITIONS=$(kubectl get application "$name" -n argocd -o jsonpath='{.status.conditions[*].message}' 2>/dev/null)
        if [ -n "$CONDITIONS" ]; then
            echo -e "     ${RED}Error: $CONDITIONS${NC}"
        fi
        
        # Print operation state if available
        OP_STATE=$(kubectl get application "$name" -n argocd -o jsonpath='{.status.operationState.message}' 2>/dev/null)
        if [ -n "$OP_STATE" ]; then
            echo -e "     ${RED}Operation: $OP_STATE${NC}"
        fi
    fi
done < <(echo "$APPS_JSON" | jq -r '.items[] | "\(.metadata.name)|\(.status.sync.status // "Unknown")|\(.status.health.status // "Unknown")"')

echo ""
echo -e "${YELLOW}Debug commands:${NC}"
echo "  kubectl get applications -n argocd"
echo "  kubectl describe application <app-name> -n argocd"
echo ""

exit 1
