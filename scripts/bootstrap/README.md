# Bootstrap Scripts

These scripts are for **one-time cluster initialization only**. After bootstrap, everything is managed via GitOps (ArgoCD).

## Essential Scripts

### 1. `01-master-bootstrap.sh`
**Purpose:** Complete cluster setup (control plane + optional workers)  
**Usage:** `./01-master-bootstrap.sh <server-ip> <root-password> [--worker-nodes <list>]`  
**When:** First time cluster creation  
**What it does:**
- Installs Talos on control plane node
- Bootstraps Kubernetes cluster
- Installs ArgoCD
- Optionally installs worker nodes
- ArgoCD deploys all platform components

### 2. `02-install-talos-rescue.sh`
**Purpose:** Install Talos OS on a rescue-mode server  
**Usage:** Called by master bootstrap script  
**When:** Provisioning new nodes (manual, outside GitOps)

### 3. `03-install-argocd.sh`
**Purpose:** Install ArgoCD and apply root Application  
**Usage:** Called by master bootstrap script  
**When:** Initial cluster setup

### 4. `03-inject-secrets.sh`
**Purpose:** Inject AWS credentials for External Secrets Operator  
**Usage:** `./03-inject-secrets.sh <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY>`  
**When:** After cluster bootstrap, before ESO can sync secrets from AWS SSM

### 5. `04-add-worker-node.sh`
**Purpose:** Add a worker node to existing cluster  
**Usage:** `./04-add-worker-node.sh --node-name worker01 --node-ip <IP> --node-role database --server-password <PASS>`  
**When:** Scaling cluster capacity (infrastructure operation)  
**What it does:**
- Installs Talos on new server
- Applies worker configuration
- Joins node to cluster

## What's NOT Here (By Design)

### ❌ Foundation/Database Deployment
**Why removed:** These are managed by ArgoCD via `platform-bootstrap` Application.  
**How to deploy:** Commit manifests to Git, ArgoCD syncs automatically.

### ❌ Post-Reboot Verification
**Why removed:** Use `scripts/validate-cluster.sh` instead.

## GitOps Workflow

After bootstrap:
1. All changes go through Git commits
2. ArgoCD syncs automatically
3. No manual kubectl/helm commands
4. Validation via `scripts/validate-cluster.sh`

## Directory Structure

```
scripts/
├── bootstrap/          # One-time cluster initialization
│   ├── 01-master-bootstrap.sh         # Initial cluster setup
│   ├── 01-master-bootstrap-examples.md # Usage examples
│   ├── 02-install-talos-rescue.sh     # Talos installation
│   ├── 02-install-talos-examples.md   # Usage examples
│   ├── 03-install-argocd.sh           # ArgoCD bootstrap
│   ├── 03-inject-secrets.sh           # ESO credentials
│   ├── 03-inject-secrets-examples.md  # Usage examples
│   ├── 04-add-worker-node.sh          # Add worker nodes
│   └── 04-add-worker-examples.md      # Usage examples
└── validate-cluster.sh # Post-sync validation
```
