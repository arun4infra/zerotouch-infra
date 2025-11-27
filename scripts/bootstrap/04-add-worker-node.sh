#!/bin/bash
# Add Worker Node Script for BizMatters Infrastructure
# Usage: ./04-add-worker-node.sh --node-name <name> --node-ip <ip> --node-role <role> --server-password <password>
#
# This script adds a worker node to an existing Talos cluster

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 --node-name <NAME> --node-ip <IP> --node-role <ROLE> --server-password <PASSWORD>

Required Arguments:
  --node-name <NAME>          Node identifier (e.g., worker01-db)
  --node-ip <IP>              Node IP address
  --node-role <ROLE>          Node role (database, compute, etc.)
  --server-password <PASS>    Rescue mode password

Example:
  $0 --node-name worker01-db --node-ip 95.216.151.243 --node-role database --server-password 'rescue123'
EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --node-name)
            NODE_NAME="$2"
            shift 2
            ;;
        --node-ip)
            NODE_IP="$2"
            shift 2
            ;;
        --node-role)
            NODE_ROLE="$2"
            shift 2
            ;;
        --server-password)
            SERVER_PASSWORD="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$NODE_NAME" || -z "$NODE_IP" || -z "$NODE_ROLE" || -z "$SERVER_PASSWORD" ]]; then
    log_error "Missing required arguments"
    usage
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log_info "Adding worker node to cluster"
log_info "Node Name: $NODE_NAME"
log_info "Node IP: $NODE_IP"
log_info "Node Role: $NODE_ROLE"

# Step 1: Validate cluster is accessible
log_info "Step 1: Validating cluster access..."
if ! kubectl get nodes &> /dev/null; then
    log_error "Cannot access cluster. Is kubeconfig configured?"
    exit 1
fi
log_info "✓ Cluster is accessible"

# Step 2: Check if node config exists
CONFIG_PATH="$SCRIPT_DIR/../../bootstrap/talos/nodes/$NODE_NAME/config.yaml"
if [ ! -f "$CONFIG_PATH" ]; then
    log_error "Node configuration not found at: $CONFIG_PATH"
    log_error "Please create the configuration file first"
    exit 1
fi
log_info "✓ Node configuration found"

# Step 3: Install Talos on worker
log_info "Step 2: Installing Talos on worker node..."
cd "$SCRIPT_DIR"
./01-install-talos-rescue.sh \
    --server-ip "$NODE_IP" \
    --user root \
    --password "$SERVER_PASSWORD" \
    --yes

log_info "✓ Talos installation complete"

# Step 4: Wait for Talos to boot
log_info "Step 3: Waiting 3 minutes for Talos to boot..."
sleep 180

# Step 5: Apply worker configuration
log_info "Step 4: Applying worker configuration..."
cd "$SCRIPT_DIR/../../bootstrap/talos"

if ! talosctl apply-config --insecure \
    --nodes "$NODE_IP" \
    --endpoints "$NODE_IP" \
    --file "nodes/$NODE_NAME/config.yaml"; then
    log_warn "Failed to apply config. Waiting 30s and retrying..."
    sleep 30
    talosctl apply-config --insecure \
        --nodes "$NODE_IP" \
        --endpoints "$NODE_IP" \
        --file "nodes/$NODE_NAME/config.yaml"
fi

log_info "✓ Configuration applied"

# Step 6: Wait for node to join
log_info "Step 5: Waiting 60 seconds for node to join cluster..."
sleep 60

# Step 7: Verify node joined and reached Ready status
log_info "Step 6: Verifying node status..."
MAX_RETRIES=10
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if kubectl get node "$NODE_NAME" &> /dev/null; then
        log_info "✓ Node $NODE_NAME has joined the cluster"
        
        # Check if node is Ready
        NODE_STATUS=$(kubectl get node "$NODE_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
        if [ "$NODE_STATUS" == "True" ]; then
            log_info "✓ Node $NODE_NAME is Ready"
            break
        else
            log_warn "Node $NODE_NAME is not Ready yet. Waiting..."
            sleep 30
            RETRY_COUNT=$((RETRY_COUNT + 1))
        fi
    else
        log_warn "Node $NODE_NAME not found yet. Waiting..."
        sleep 30
        RETRY_COUNT=$((RETRY_COUNT + 1))
    fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    log_error "Node did not reach Ready status within expected time"
    log_error "Check node status with: kubectl get nodes"
    exit 1
fi

# Step 8: Verify labels and taints
log_info "Step 7: Verifying node labels and taints..."
kubectl get node "$NODE_NAME" -o yaml | grep -A 5 "labels:" || true
kubectl get node "$NODE_NAME" -o yaml | grep -A 5 "taints:" || true

# Final summary
echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Worker Node Added Successfully!                     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ Node Name: $NODE_NAME${NC}"
echo -e "${GREEN}✓ Node IP: $NODE_IP${NC}"
echo -e "${GREEN}✓ Node Role: $NODE_ROLE${NC}"
echo -e "${GREEN}✓ Status: Ready${NC}"
echo ""
echo -e "${YELLOW}Verify with:${NC}"
echo -e "  kubectl get nodes"
echo -e "  kubectl describe node $NODE_NAME"
echo ""
