#!/bin/bash
# Shared Diagnostics Library for Bootstrap Scripts
# Usage: source helpers/diagnostics.sh
#
# Provides comprehensive diagnostic functions for ArgoCD apps and Kubernetes resources.

# Colors (define if not already set)
RED=${RED:-'\033[0;31m'}
GREEN=${GREEN:-'\033[0;32m'}
YELLOW=${YELLOW:-'\033[1;33m'}
BLUE=${BLUE:-'\033[0;34m'}
CYAN=${CYAN:-'\033[0;36m'}
NC=${NC:-'\033[0m'}

# ============================================================================
# KUBECTL HELPERS
# ============================================================================

# Retry kubectl commands with exponential backoff
kubectl_retry() {
    local max_attempts=${KUBECTL_MAX_ATTEMPTS:-5}
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        if kubectl "$@" 2>/dev/null; then
            return 0
        fi
        sleep $((attempt * 2))
        attempt=$((attempt + 1))
    done
    return 1
}

# ============================================================================
# ARGOCD APPLICATION DIAGNOSTICS
# ============================================================================

# Get detailed diagnostics for an ArgoCD application
# Usage: diagnose_argocd_app <app_name> [namespace]
diagnose_argocd_app() {
    local app_name="$1"
    local namespace="${2:-argocd}"
    
    local APP_JSON=$(kubectl get application "$app_name" -n "$namespace" -o json 2>/dev/null)
    if [ -z "$APP_JSON" ] || [ "$APP_JSON" = "null" ]; then
        echo -e "       ${RED}Could not fetch application details${NC}"
        return 1
    fi
    
    local sync_status=$(echo "$APP_JSON" | jq -r '.status.sync.status // "Unknown"')
    local health_status=$(echo "$APP_JSON" | jq -r '.status.health.status // "Unknown"')
    
    # 1. Show sync/health status
    echo -e "       ${CYAN}Status: $sync_status / $health_status${NC}"
    
    # 2. Show app-level health message if present
    local health_msg=$(echo "$APP_JSON" | jq -r '.status.health.message // empty')
    if [ -n "$health_msg" ]; then
        echo -e "       ${YELLOW}Health Message: $health_msg${NC}"
    fi
    
    # 3. Show conditions (sync errors, warnings, etc.)
    local conditions=$(echo "$APP_JSON" | jq -r '.status.conditions[]? | "         - [\(.type)] \(.message // "no message")"' 2>/dev/null)
    if [ -n "$conditions" ]; then
        echo -e "       ${YELLOW}Conditions:${NC}"
        echo "$conditions" | head -5
    fi
    
    # 4. Show operation state (sync operations)
    local op_phase=$(echo "$APP_JSON" | jq -r '.status.operationState.phase // "none"')
    local op_msg=$(echo "$APP_JSON" | jq -r '.status.operationState.message // empty')
    local op_started=$(echo "$APP_JSON" | jq -r '.status.operationState.startedAt // empty')
    
    if [ "$op_phase" != "none" ] && [ "$op_phase" != "Succeeded" ]; then
        echo -e "       ${YELLOW}Operation State:${NC}"
        echo -e "         Phase: $op_phase"
        [ -n "$op_started" ] && echo -e "         Started: $op_started"
        [ -n "$op_msg" ] && echo -e "         Message: ${op_msg:0:200}"
        
        # Show sync result details if failed
        if [ "$op_phase" = "Failed" ] || [ "$op_phase" = "Error" ]; then
            local sync_results=$(echo "$APP_JSON" | jq -r '.status.operationState.syncResult.resources[]? | select(.status != "Synced") | "         - \(.kind)/\(.name): \(.status) - \(.message // "no message")"' 2>/dev/null | head -5)
            if [ -n "$sync_results" ]; then
                echo -e "       ${RED}Failed Resources:${NC}"
                echo "$sync_results"
            fi
        fi
    fi
    
    # 5. Show resource breakdown by health status
    _show_resource_breakdown "$APP_JSON" "$sync_status" "$health_status"
    
    # 6. Show recent events for the app's namespace
    local app_namespace=$(echo "$APP_JSON" | jq -r '.spec.destination.namespace // "default"')
    _show_namespace_events "$app_namespace" "$app_name"
}

# Internal: Show resource breakdown
_show_resource_breakdown() {
    local APP_JSON="$1"
    local sync_status="$2"
    local health_status="$3"
    
    # Count resources by status
    local total_resources=$(echo "$APP_JSON" | jq -r '.status.resources | length // 0')
    
    if [ "$total_resources" -eq 0 ]; then
        echo -e "       ${YELLOW}No resources found in application${NC}"
        return
    fi
    
    # Show OutOfSync resources
    if [[ "$sync_status" == *"OutOfSync"* ]]; then
        local outofsync=$(echo "$APP_JSON" | jq -r '.status.resources[]? | select(.status == "OutOfSync") | "         - \(.kind)/\(.name): \(.message // "needs sync")"' 2>/dev/null | head -5)
        if [ -n "$outofsync" ]; then
            echo -e "       ${RED}OutOfSync Resources:${NC}"
            echo "$outofsync"
        fi
    fi
    
    # Show Degraded resources
    if [[ "$health_status" == *"Degraded"* ]]; then
        local degraded=$(echo "$APP_JSON" | jq -r '.status.resources[]? | select(.health.status == "Degraded") | "         - \(.kind)/\(.name): \(.health.message // "degraded")"' 2>/dev/null | head -5)
        if [ -n "$degraded" ]; then
            echo -e "       ${RED}Degraded Resources:${NC}"
            echo "$degraded"
        fi
    fi
    
    # Show Progressing resources
    if [[ "$health_status" == *"Progressing"* ]]; then
        local progressing=$(echo "$APP_JSON" | jq -r '.status.resources[]? | select(.health.status == "Progressing") | "         - \(.kind)/\(.name): \(.health.message // "in progress")"' 2>/dev/null | head -5)
        if [ -n "$progressing" ]; then
            echo -e "       ${BLUE}Progressing Resources:${NC}"
            echo "$progressing"
        else
            # No individual resources marked progressing - show full breakdown
            echo -e "       ${BLUE}Resource Health Breakdown:${NC}"
            echo "$APP_JSON" | jq -r '
                .status.resources[]? | 
                select(.health.status != "Healthy") |
                "         - \(.kind)/\(.name): \(.health.status // "Unknown") - \(.health.message // "no message")"
            ' 2>/dev/null | head -8
            
            # If still nothing, show summary counts
            if [ -z "$(echo "$APP_JSON" | jq -r '.status.resources[]? | select(.health.status != "Healthy")')" ]; then
                echo -e "         ${CYAN}All $total_resources resources report Healthy but app is Progressing${NC}"
                echo -e "         ${CYAN}This usually means a controller is still reconciling${NC}"
            fi
        fi
    fi
    
    # Show Missing resources
    local missing=$(echo "$APP_JSON" | jq -r '.status.resources[]? | select(.health.status == "Missing") | "         - \(.kind)/\(.name)"' 2>/dev/null | head -3)
    if [ -n "$missing" ]; then
        echo -e "       ${RED}Missing Resources:${NC}"
        echo "$missing"
    fi
    
    # Show Unknown health resources
    local unknown=$(echo "$APP_JSON" | jq -r '.status.resources[]? | select(.health.status == "Unknown") | "         - \(.kind)/\(.name): \(.health.message // "unknown state")"' 2>/dev/null | head -3)
    if [ -n "$unknown" ]; then
        echo -e "       ${YELLOW}Unknown Health Resources:${NC}"
        echo "$unknown"
    fi
}

# Internal: Show recent events for a namespace
_show_namespace_events() {
    local namespace="$1"
    local app_name="$2"
    
    # Get warning events from the namespace
    local events=$(kubectl get events -n "$namespace" --field-selector type=Warning --sort-by='.lastTimestamp' -o json 2>/dev/null | \
        jq -r '.items[-5:][] | "         - [\(.involvedObject.kind)/\(.involvedObject.name)] \(.reason): \(.message | .[0:100])"' 2>/dev/null)
    
    if [ -n "$events" ]; then
        echo -e "       ${YELLOW}Recent Warning Events ($namespace):${NC}"
        echo "$events"
    fi
}

# ============================================================================
# KUBERNETES RESOURCE DIAGNOSTICS
# ============================================================================

# Diagnose a StatefulSet
# Usage: diagnose_statefulset <name> <namespace>
diagnose_statefulset() {
    local name="$1"
    local namespace="$2"
    
    local sts_json=$(kubectl get statefulset "$name" -n "$namespace" -o json 2>/dev/null)
    if [ -z "$sts_json" ]; then
        echo -e "       ${RED}StatefulSet not found${NC}"
        return 1
    fi
    
    local ready=$(echo "$sts_json" | jq -r '.status.readyReplicas // 0')
    local replicas=$(echo "$sts_json" | jq -r '.spec.replicas // 0')
    local current=$(echo "$sts_json" | jq -r '.status.currentReplicas // 0')
    local updated=$(echo "$sts_json" | jq -r '.status.updatedReplicas // 0')
    
    echo -e "       ${CYAN}Replicas: $ready/$replicas ready (current: $current, updated: $updated)${NC}"
    
    if [ "$ready" -ne "$replicas" ]; then
        # Show pod status
        echo -e "       ${YELLOW}Pod Status:${NC}"
        kubectl get pods -n "$namespace" -l "app.kubernetes.io/name=$name" -o wide 2>/dev/null | head -5 | while read -r line; do
            echo -e "         $line"
        done
        
        # Show pending/failed pods details
        local problem_pods=$(kubectl get pods -n "$namespace" -l "app.kubernetes.io/name=$name" -o json 2>/dev/null | \
            jq -r '.items[] | select(.status.phase != "Running") | "\(.metadata.name): \(.status.phase) - \(.status.conditions[]? | select(.status != "True") | .message // "waiting")"' 2>/dev/null | head -3)
        if [ -n "$problem_pods" ]; then
            echo -e "       ${RED}Problem Pods:${NC}"
            echo "$problem_pods" | while read -r line; do
                echo -e "         - $line"
            done
        fi
        
        # Check PVCs
        _diagnose_pvcs "$namespace" "app.kubernetes.io/name=$name"
    fi
}

# Diagnose a Deployment
# Usage: diagnose_deployment <name> <namespace>
diagnose_deployment() {
    local name="$1"
    local namespace="$2"
    
    local deploy_json=$(kubectl get deployment "$name" -n "$namespace" -o json 2>/dev/null)
    if [ -z "$deploy_json" ]; then
        echo -e "       ${RED}Deployment not found${NC}"
        return 1
    fi
    
    local ready=$(echo "$deploy_json" | jq -r '.status.readyReplicas // 0')
    local replicas=$(echo "$deploy_json" | jq -r '.spec.replicas // 0')
    local available=$(echo "$deploy_json" | jq -r '.status.availableReplicas // 0')
    local unavailable=$(echo "$deploy_json" | jq -r '.status.unavailableReplicas // 0')
    
    echo -e "       ${CYAN}Replicas: $ready/$replicas ready (available: $available, unavailable: $unavailable)${NC}"
    
    # Show conditions
    local conditions=$(echo "$deploy_json" | jq -r '.status.conditions[]? | select(.status != "True") | "         - \(.type): \(.message // "no message")"' 2>/dev/null)
    if [ -n "$conditions" ]; then
        echo -e "       ${YELLOW}Conditions:${NC}"
        echo "$conditions"
    fi
    
    if [ "$ready" -ne "$replicas" ]; then
        # Show pod status
        echo -e "       ${YELLOW}Pod Status:${NC}"
        kubectl get pods -n "$namespace" -l "app.kubernetes.io/name=$name" -o wide 2>/dev/null | head -5 | while read -r line; do
            echo -e "         $line"
        done
    fi
}

# Internal: Diagnose PVCs
_diagnose_pvcs() {
    local namespace="$1"
    local selector="$2"
    
    local pvcs=$(kubectl get pvc -n "$namespace" ${selector:+-l "$selector"} -o json 2>/dev/null)
    local pending_pvcs=$(echo "$pvcs" | jq -r '.items[] | select(.status.phase != "Bound") | "\(.metadata.name): \(.status.phase)"' 2>/dev/null)
    
    if [ -n "$pending_pvcs" ]; then
        echo -e "       ${RED}Pending PVCs:${NC}"
        echo "$pending_pvcs" | while read -r line; do
            echo -e "         - $line"
        done
        
        # Check for storage class issues
        local sc_name=$(echo "$pvcs" | jq -r '.items[0].spec.storageClassName // "default"' 2>/dev/null)
        if ! kubectl get storageclass "$sc_name" >/dev/null 2>&1; then
            echo -e "         ${RED}StorageClass '$sc_name' not found!${NC}"
        fi
        
        # Show PVC events
        echo -e "       ${YELLOW}PVC Events:${NC}"
        kubectl get events -n "$namespace" --field-selector reason=ProvisioningFailed --sort-by='.lastTimestamp' 2>/dev/null | tail -3 | while read -r line; do
            echo -e "         $line"
        done
    fi
}

# ============================================================================
# SERVICE-SPECIFIC DIAGNOSTICS
# ============================================================================

# Diagnose PostgreSQL (CNPG) cluster
# Usage: diagnose_postgres <cluster_name> <namespace>
diagnose_postgres() {
    local name="$1"
    local namespace="$2"
    
    local cluster_json=$(kubectl get clusters.postgresql.cnpg.io "$name" -n "$namespace" -o json 2>/dev/null)
    if [ -z "$cluster_json" ]; then
        echo -e "       ${RED}PostgreSQL cluster not found${NC}"
        return 1
    fi
    
    local phase=$(echo "$cluster_json" | jq -r '.status.phase // "Unknown"')
    local ready=$(echo "$cluster_json" | jq -r '.status.readyInstances // 0')
    local total=$(echo "$cluster_json" | jq -r '.status.instances // 0')
    
    echo -e "       ${CYAN}Phase: $phase ($ready/$total instances ready)${NC}"
    
    # Show conditions
    local conditions=$(echo "$cluster_json" | jq -r '.status.conditions[]? | select(.status != "True") | "         - \(.type): \(.message // "no message")"' 2>/dev/null)
    if [ -n "$conditions" ]; then
        echo -e "       ${YELLOW}Conditions:${NC}"
        echo "$conditions"
    fi
    
    if [ "$phase" != "Cluster in healthy state" ]; then
        # Show pod status
        echo -e "       ${YELLOW}Pod Status:${NC}"
        kubectl get pods -n "$namespace" -l "cnpg.io/cluster=$name" -o wide 2>/dev/null | while read -r line; do
            echo -e "         $line"
        done
        
        # Check PVCs
        _diagnose_pvcs "$namespace" "cnpg.io/cluster=$name"
    fi
}

# Diagnose NATS cluster
# Usage: diagnose_nats [namespace]
diagnose_nats() {
    local namespace="${1:-nats}"
    
    diagnose_statefulset "nats" "$namespace"
    
    # Additional NATS-specific checks
    local nats_box=$(kubectl get pods -n "$namespace" -l app.kubernetes.io/name=nats-box -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$nats_box" ]; then
        echo -e "       ${CYAN}NATS Box available for debugging: kubectl exec -n $namespace $nats_box -- nats server check${NC}"
    fi
}

# Diagnose Dragonfly cache
# Usage: diagnose_dragonfly <name> <namespace>
diagnose_dragonfly() {
    local name="$1"
    local namespace="$2"
    
    diagnose_statefulset "$name" "$namespace"
}

# ============================================================================
# SUMMARY DIAGNOSTICS
# ============================================================================

# Print a diagnostic summary for multiple unhealthy apps
# Usage: print_diagnostic_summary <app_list_json>
print_diagnostic_summary() {
    local apps_json="$1"
    
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Diagnostic Summary                                         ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Count by status
    local total=$(echo "$apps_json" | jq -r '.items | length')
    local healthy=$(echo "$apps_json" | jq -r '[.items[] | select(.status.sync.status == "Synced" and .status.health.status == "Healthy")] | length')
    local progressing=$(echo "$apps_json" | jq -r '[.items[] | select(.status.health.status == "Progressing")] | length')
    local degraded=$(echo "$apps_json" | jq -r '[.items[] | select(.status.health.status == "Degraded")] | length')
    local outofsync=$(echo "$apps_json" | jq -r '[.items[] | select(.status.sync.status == "OutOfSync")] | length')
    
    echo -e "   ${GREEN}Healthy:${NC}     $healthy/$total"
    echo -e "   ${BLUE}Progressing:${NC} $progressing"
    echo -e "   ${RED}Degraded:${NC}    $degraded"
    echo -e "   ${RED}OutOfSync:${NC}   $outofsync"
    echo ""
    
    # Common issues detection
    echo -e "${YELLOW}Common Issues Detected:${NC}"
    
    # Check for PVC issues
    local pending_pvcs=$(kubectl get pvc --all-namespaces --field-selector status.phase=Pending -o name 2>/dev/null | wc -l)
    if [ "$pending_pvcs" -gt 0 ]; then
        echo -e "   ${RED}⚠ $pending_pvcs PVCs pending - check storage provisioner${NC}"
    fi
    
    # Check for image pull issues
    local image_pull_errors=$(kubectl get events --all-namespaces --field-selector reason=Failed -o json 2>/dev/null | jq -r '[.items[] | select(.message | contains("ImagePull") or contains("ErrImagePull"))] | length')
    if [ "$image_pull_errors" -gt 0 ]; then
        echo -e "   ${RED}⚠ Image pull errors detected - check registry access${NC}"
    fi
    
    # Check for resource quota issues
    local quota_errors=$(kubectl get events --all-namespaces --field-selector reason=FailedCreate -o json 2>/dev/null | jq -r '[.items[] | select(.message | contains("quota") or contains("exceeded"))] | length')
    if [ "$quota_errors" -gt 0 ]; then
        echo -e "   ${RED}⚠ Resource quota exceeded - check namespace quotas${NC}"
    fi
    
    echo ""
}

# ============================================================================
# DEBUG COMMANDS HELPER
# ============================================================================

# Print helpful debug commands
print_debug_commands() {
    echo -e "${YELLOW}Debug Commands:${NC}"
    echo "  # ArgoCD Applications"
    echo "  kubectl get applications -n argocd"
    echo "  kubectl describe application <app-name> -n argocd"
    echo "  argocd app get <app-name> --show-operation"
    echo ""
    echo "  # Pods & Events"
    echo "  kubectl get pods -A | grep -v Running"
    echo "  kubectl get events -A --sort-by='.lastTimestamp' | tail -20"
    echo ""
    echo "  # Storage"
    echo "  kubectl get pvc -A"
    echo "  kubectl get storageclass"
    echo ""
}

# ============================================================================
# CLUSTER-WIDE DIAGNOSTICS
# ============================================================================

# Show cluster resource status overview
# Usage: show_cluster_status
show_cluster_status() {
    echo -e "${BLUE}Cluster resource status:${NC}"
    
    echo -e "  ${YELLOW}Nodes:${NC}"
    kubectl_retry get nodes -o wide 2>/dev/null | while read -r node; do
        echo -e "    $node"
    done || echo -e "    ${YELLOW}Could not get nodes${NC}"
    
    echo -e "  ${YELLOW}Storage classes:${NC}"
    kubectl_retry get storageclass 2>/dev/null | while read -r sc; do
        echo -e "    $sc"
    done || echo -e "    ${YELLOW}Could not get storage classes${NC}"
    
    echo -e "  ${YELLOW}Node resource usage:${NC}"
    kubectl_retry top nodes 2>/dev/null | while read -r usage; do
        echo -e "    $usage"
    done || echo -e "    ${YELLOW}Metrics not available${NC}"
    
    echo ""
}

# Show detailed PostgreSQL diagnostics
# Usage: show_postgres_details <namespace> <cluster_name>
show_postgres_details() {
    local namespace="$1"
    local cluster_name="$2"
    
    echo -e "     ${YELLOW}PostgreSQL cluster details:${NC}"
    local cluster_json=$(kubectl_retry get clusters.postgresql.cnpg.io "$cluster_name" -n "$namespace" -o json 2>/dev/null)
    if [ -n "$cluster_json" ]; then
        echo "$cluster_json" | jq -r '"       Phase: \(.status.phase)\n       Instances: \(.status.readyInstances)/\(.status.instances)\n       Conditions: \(.status.conditions // [] | map("\(.type)=\(.status): \(.message)") | join(", "))"' 2>/dev/null || echo -e "       ${YELLOW}Could not parse cluster details${NC}"
    fi
    
    echo -e "     ${YELLOW}PostgreSQL pod status:${NC}"
    kubectl_retry get pods -n "$namespace" -l cnpg.io/cluster="$cluster_name" -o wide 2>/dev/null | head -10 | while read -r pod; do
        echo -e "       $pod"
    done || echo -e "       ${YELLOW}No PostgreSQL pods found${NC}"
    
    # Show detailed pod info for pending/failed pods
    local problem_pods=$(kubectl_retry get pods -n "$namespace" -l cnpg.io/cluster="$cluster_name" --field-selector=status.phase!=Running,status.phase!=Succeeded -o json 2>/dev/null)
    if [ -n "$problem_pods" ] && [ "$(echo "$problem_pods" | jq -r '.items | length')" -gt 0 ]; then
        echo -e "     ${YELLOW}Problem pod details:${NC}"
        echo "$problem_pods" | jq -r '.items[] | "       Pod: \(.metadata.name)\n       Phase: \(.status.phase)\n       Reason: \(.status.reason // "N/A")\n       Message: \(.status.message // "N/A")\n       Conditions: \(.status.conditions // [] | map("\(.type)=\(.status): \(.reason)") | join(", "))"' 2>/dev/null | head -20 || echo -e "       ${YELLOW}Could not parse pod details${NC}"
    fi
}

# Show detailed PVC diagnostics
# Usage: show_pvc_details <namespace> <label_selector>
show_pvc_details() {
    local namespace="$1"
    local label_selector="$2"
    
    echo -e "     ${YELLOW}PVC status:${NC}"
    kubectl_retry get pvc -n "$namespace" ${label_selector:+-l "$label_selector"} 2>/dev/null | head -5 | while read -r pvc; do
        echo -e "       $pvc"
    done || echo -e "       ${YELLOW}No PVCs found${NC}"
    
    # Show detailed PVC info for pending PVCs
    local pending_pvcs=$(kubectl_retry get pvc -n "$namespace" ${label_selector:+-l "$label_selector"} --field-selector=status.phase=Pending -o json 2>/dev/null)
    if [ -n "$pending_pvcs" ] && [ "$(echo "$pending_pvcs" | jq -r '.items | length')" -gt 0 ]; then
        echo -e "     ${YELLOW}Pending PVC details:${NC}"
        echo "$pending_pvcs" | jq -r '.items[] | "       PVC: \(.metadata.name)\n       StorageClass: \(.spec.storageClassName)\n       Status: \(.status.phase)\n       Conditions: \(.status.conditions // [] | map("\(.type)=\(.status): \(.message)") | join(", "))"' 2>/dev/null || echo -e "       ${YELLOW}Could not parse PVC details${NC}"
    fi
}

# Show detailed pod diagnostics
# Usage: show_pod_details <namespace> <label_selector>
show_pod_details() {
    local namespace="$1"
    local label_selector="$2"
    
    echo -e "     ${YELLOW}Pod status:${NC}"
    kubectl_retry get pods -n "$namespace" ${label_selector:+-l "$label_selector"} -o wide 2>/dev/null | head -10 | while read -r pod; do
        echo -e "       $pod"
    done || echo -e "       ${YELLOW}No pods found${NC}"
}

# Show detailed NATS diagnostics
# Usage: show_nats_details <namespace>
show_nats_details() {
    local namespace="$1"
    
    echo -e "     ${YELLOW}NATS pod status:${NC}"
    kubectl_retry get pods -n "$namespace" -l app.kubernetes.io/name=nats -o wide 2>/dev/null | head -5 | while read -r pod; do
        echo -e "       $pod"
    done || echo -e "       ${YELLOW}No pods found${NC}"
    
    # Show detailed pod info
    local nats_pods=$(kubectl_retry get pods -n "$namespace" -l app.kubernetes.io/name=nats -o json 2>/dev/null)
    if [ -n "$nats_pods" ] && [ "$(echo "$nats_pods" | jq -r '.items | length')" -gt 0 ]; then
        echo -e "     ${YELLOW}Detailed pod info:${NC}"
        echo "$nats_pods" | jq -r '.items[] | "       Pod: \(.metadata.name)\n       Phase: \(.status.phase)\n       Containers: \(.status.containerStatuses // [] | map("\(.name): ready=\(.ready), restarts=\(.restartCount)") | join(", "))\n       Conditions: \(.status.conditions // [] | map("\(.type)=\(.status)") | join(", "))"' 2>/dev/null | head -20
    fi
    
    # Show waiting containers
    local waiting=$(kubectl get pods -n "$namespace" -o json 2>/dev/null | \
        jq -r '.items[]? | select(.status.containerStatuses[]?.ready == false) | 
        "       \(.metadata.name): \(.status.containerStatuses[]? | select(.ready == false) | .state | to_entries[0] | "\(.key): \(.value.reason // .value.message // "waiting")")"' 2>/dev/null | head -3)
    [ -n "$waiting" ] && echo -e "     ${YELLOW}Waiting containers:${NC}" && echo "$waiting"
    
    # Show PVC status
    show_pvc_details "$namespace" ""
    
    # Show all recent events
    echo -e "     ${YELLOW}All recent events:${NC}"
    kubectl_retry get events -n "$namespace" --sort-by='.lastTimestamp' 2>/dev/null | tail -10 | while read -r event; do
        echo -e "       $event"
    done || echo -e "       ${YELLOW}No events found${NC}"
}

# Show storage class information
# Usage: show_storage_classes
show_storage_classes() {
    echo -e "     ${YELLOW}Storage classes:${NC}"
    kubectl_retry get storageclass 2>/dev/null | while read -r sc; do
        echo -e "       $sc"
    done || echo -e "       ${YELLOW}Could not get storage classes${NC}"
}

# Show recent events with filtering
# Usage: show_recent_events <namespace> <grep_pattern> <count>
show_recent_events() {
    local namespace="$1"
    local pattern="$2"
    local count="${3:-10}"
    
    echo -e "     ${YELLOW}Recent events:${NC}"
    if [ "$namespace" = "--all-namespaces" ]; then
        kubectl_retry get events --all-namespaces --sort-by='.lastTimestamp' 2>/dev/null | grep -iE "$pattern" | tail -"$count" | while read -r event; do
            echo -e "       $event"
        done || echo -e "       ${YELLOW}No recent events found${NC}"
    else
        kubectl_retry get events -n "$namespace" --sort-by='.lastTimestamp' 2>/dev/null | grep -iE "$pattern" | tail -"$count" | while read -r event; do
            echo -e "       $event"
        done || echo -e "       ${YELLOW}No recent events found${NC}"
    fi
}

# ============================================================================
# TIMEOUT DIAGNOSTICS (COMPREHENSIVE)
# ============================================================================

# Show comprehensive diagnostics on timeout
# Usage: show_timeout_diagnostics
show_timeout_diagnostics() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   DETAILED DIAGNOSTICS                                       ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${BLUE}PostgreSQL Clusters:${NC}"
    kubectl_retry get clusters.postgresql.cnpg.io --all-namespaces -o wide 2>/dev/null || echo "No PostgreSQL clusters found"
    echo ""
    
    echo -e "${BLUE}PostgreSQL Cluster Details:${NC}"
    kubectl_retry get clusters.postgresql.cnpg.io --all-namespaces -o json 2>/dev/null | jq -r '.items[] | "Cluster: \(.metadata.namespace)/\(.metadata.name)\nPhase: \(.status.phase)\nInstances: \(.status.readyInstances)/\(.status.instances)\nConditions: \(.status.conditions // [] | map("\(.type)=\(.status): \(.message)") | join(", "))\n"' 2>/dev/null || echo "Could not get cluster details"
    echo ""
    
    echo -e "${BLUE}PostgreSQL Pods:${NC}"
    kubectl_retry get pods --all-namespaces -l cnpg.io/cluster -o wide 2>/dev/null || echo "No PostgreSQL pods found"
    echo ""
    
    echo -e "${BLUE}PostgreSQL PVCs:${NC}"
    kubectl_retry get pvc --all-namespaces -l cnpg.io/cluster -o wide 2>/dev/null || echo "No PostgreSQL PVCs found"
    echo ""
    
    echo -e "${BLUE}Dragonfly Caches:${NC}"
    kubectl_retry get statefulsets --all-namespaces -l app=dragonfly -o wide 2>/dev/null || echo "No Dragonfly caches found"
    echo ""
    
    echo -e "${BLUE}Dragonfly Pods:${NC}"
    kubectl_retry get pods --all-namespaces -l app=dragonfly -o wide 2>/dev/null || echo "No Dragonfly pods found"
    echo ""
    
    echo -e "${BLUE}NATS Messaging:${NC}"
    kubectl_retry get statefulset nats -n nats -o wide 2>/dev/null || echo "No NATS found"
    echo ""
    
    echo -e "${BLUE}NATS Pods:${NC}"
    kubectl_retry get pods -n nats -l app.kubernetes.io/name=nats -o wide 2>/dev/null || echo "No NATS pods found"
    echo ""
    
    echo -e "${BLUE}External Secrets:${NC}"
    kubectl_retry get externalsecrets --all-namespaces -o wide 2>/dev/null || echo "No ExternalSecrets found"
    echo ""
    
    echo -e "${BLUE}ClusterSecretStore Status:${NC}"
    kubectl_retry get clustersecretstore aws-parameter-store -o jsonpath='{.status}' 2>/dev/null | jq '.' 2>/dev/null || echo "ClusterSecretStore not found or invalid"
    echo ""
    
    echo -e "${BLUE}All PVCs in cluster:${NC}"
    kubectl_retry get pvc --all-namespaces -o wide 2>/dev/null || echo "No PVCs found"
    echo ""
    
    echo -e "${BLUE}Pending PVCs (detailed):${NC}"
    kubectl_retry get pvc --all-namespaces --field-selector=status.phase=Pending -o json 2>/dev/null | jq -r '.items[] | "PVC: \(.metadata.namespace)/\(.metadata.name)\nStorageClass: \(.spec.storageClassName)\nStatus: \(.status.phase)\nRequested: \(.spec.resources.requests.storage)\nAccessModes: \(.spec.accessModes | join(", "))\nVolumeMode: \(.spec.volumeMode)\n"' 2>/dev/null || echo "No pending PVCs or could not parse"
    echo ""
    
    echo -e "${BLUE}Recent Events (last 20):${NC}"
    kubectl_retry get events --all-namespaces --sort-by='.lastTimestamp' | tail -20 2>/dev/null || echo "No events found"
    echo ""
    
    echo -e "${BLUE}ArgoCD Application Status:${NC}"
    kubectl_retry get applications -n argocd -o wide 2>/dev/null || echo "No ArgoCD applications found"
    echo ""
}
