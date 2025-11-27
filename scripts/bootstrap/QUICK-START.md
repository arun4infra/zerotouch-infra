# Quick Start Guide

## New Cluster Setup

### Step 1: Bootstrap Cluster

**Option A: With AWS credentials (recommended)**
```bash
# Export AWS credentials
export AWS_ACCESS_KEY_ID="your-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-key"

# Single node cluster
./scripts/bootstrap/01-master-bootstrap.sh <server-ip> <root-password>

# Multi-node cluster with workers
./scripts/bootstrap/01-master-bootstrap.sh <server-ip> <root-password> \
  --worker-nodes worker01:95.216.151.243 \
  --worker-password <worker-password>
```

**Option B: Inject credentials manually after bootstrap**
```bash
# Bootstrap without credentials
./scripts/bootstrap/01-master-bootstrap.sh <server-ip> <root-password>

# Then inject ESO credentials
./scripts/bootstrap/03-inject-secrets.sh <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY>
```

### Step 3: Verify Deployment
```bash
# Check ArgoCD applications
kubectl get applications -n argocd

# Validate cluster
./scripts/validate-cluster.sh

# Access ArgoCD UI
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Username: admin
# Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## Add Worker Node (After Initial Setup)

```bash
./scripts/bootstrap/04-add-worker-node.sh \
  --node-name worker01 \
  --node-ip 95.216.151.243 \
  --node-role intelligence \
  --server-password <password>
```

## Bootstrap Script Sequence

1. **01-master-bootstrap.sh** - Orchestrates entire setup
   - Calls 02-install-talos-rescue.sh (installs Talos)
   - Bootstraps Kubernetes cluster
   - Calls 03-install-argocd.sh (installs ArgoCD)
   - **Waits for platform-bootstrap to sync** (with timeout)
   - **Verifies all child Applications are created**
   - **Auto-injects ESO credentials** (if AWS env vars are set)
   - **Waits for ESO to become ready**
   - **Fails fast** if sync errors occur

2. **03-inject-secrets.sh** - ESO credential injection
   - Can be called automatically by master script (if AWS env vars set)
   - Or run manually after bootstrap
   - Injects AWS credentials for ESO
   - Enables secret sync from AWS SSM Parameter Store

3. **04-add-worker-node.sh** - Optional, for scaling
   - Adds additional worker nodes
   - Calls 02-install-talos-rescue.sh internally

## What Gets Deployed by ArgoCD

After bootstrap, ArgoCD automatically deploys:
- External Secrets Operator (ESO)
- Crossplane (infrastructure provisioning)
- KEDA (event-driven autoscaling)
- Kagent (AI agent platform)
- Intelligence workloads
- Database layer (if workers exist)

## Troubleshooting

```bash
# Check cluster status
kubectl get nodes
kubectl get pods -A

# Check ArgoCD sync status
kubectl get applications -n argocd

# Check ESO status
kubectl get clustersecretstore
kubectl get externalsecret -A

# Validate everything
./scripts/validate-cluster.sh
```

## Important Files

- `bootstrap/talos/talosconfig` - Talos cluster config
- `~/.kube/config` - Kubernetes config
- `bootstrap/secrets/eso-bootstrap-secret.yaml` - ESO credentials (created by inject-secrets.sh)

## AWS SSM Parameters Required

Ensure these exist in AWS SSM Parameter Store:
- `/zerotouch/prod/kagent/openai_api_key` - OpenAI API key for kagent
