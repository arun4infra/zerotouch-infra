# Preview Mode Fix - Local Path Provisioner Conflict

## Problem
GitHub Actions workflow was timing out after 11m 44s because PostgreSQL PVC remained stuck in "Pending" state.

### Root Cause
ArgoCD was trying to deploy `00-local-path-provisioner.yaml` in Kind clusters that already have a built-in local-path-provisioner (Kind v1.34+). This caused:
- Immutable field errors (spec.selector, provisioner)
- ArgoCD sync failures
- No actual breakage of the existing provisioner, BUT
- PostgreSQL pods couldn't schedule (separate issue being investigated)

## Solution Applied

### 1. Exclude local-path-provisioner from ArgoCD in Preview Mode
**File**: `bootstrap/10-platform-bootstrap.yaml`
- Changed exclude pattern from `'01-eso.yaml'` to `'01-eso.yaml|00-local-path-provisioner.yaml'`
- This prevents ArgoCD from trying to manage what Kind already provides

### 2. Enhanced Debugging with Shared Diagnostic Library
**File**: `scripts/bootstrap/helpers/diagnostics.sh`

Added comprehensive reusable diagnostic functions:

#### Cluster-Wide Diagnostics
- `show_cluster_status()` - Nodes, storage classes, resource usage
- `show_timeout_diagnostics()` - Complete cluster state on timeout

#### Service-Specific Diagnostics
- `show_postgres_details()` - Cluster phase, conditions, pods, PVCs
- `show_nats_details()` - Pod status, container states, events
- `show_pvc_details()` - PVC status with pending analysis
- `show_pod_details()` - Pod listing with wide format
- `show_storage_classes()` - Storage class configuration
- `show_recent_events()` - Filtered event history

#### Benefits
- **Reusable**: All bootstrap scripts can use these functions
- **Clean**: Wait scripts are now much cleaner and maintainable
- **Comprehensive**: Detailed diagnostics without code duplication
- **Consistent**: Same diagnostic format across all scripts

### 3. Refactored Wait Script
**File**: `scripts/bootstrap/13-wait-service-dependencies.sh`
- Replaced inline diagnostic code with function calls
- Reduced script size by ~200 lines
- Improved readability and maintainability

### 4. Updated Documentation
**File**: `scripts/bootstrap/patches/05-verify-storage-provisioner.sh`
- Updated comments to reflect that Kind v1.34+ has built-in provisioner
- Clarified that we disable our ArgoCD app to avoid conflicts

## Expected Outcome

Next workflow run will:
1. ✅ Not attempt to deploy local-path-provisioner via ArgoCD
2. ✅ Use Kind's built-in provisioner without conflicts
3. ✅ Provide detailed diagnostics if PostgreSQL PVC still fails
4. ✅ Show exact reason why pods can't schedule (node selectors, taints, resources, etc.)

## Files Changed
- `bootstrap/10-platform-bootstrap.yaml` - Excluded local-path-provisioner
- `scripts/bootstrap/13-wait-service-dependencies.sh` - Refactored to use shared diagnostics
- `scripts/bootstrap/patches/05-verify-storage-provisioner.sh` - Updated comments
- `scripts/bootstrap/helpers/diagnostics.sh` - Added comprehensive diagnostic functions

## Next Steps
If PostgreSQL PVC still fails after this fix, the enhanced logs will show:
- Exact pod scheduling failure reason
- Node resource constraints
- Storage class configuration issues
- PVC binding problems
- Container wait states and reasons
