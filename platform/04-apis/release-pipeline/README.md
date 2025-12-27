# Release Pipeline API

This directory contains Crossplane XRDs and Compositions for the centralized release pipeline system.

## Overview

The Release Pipeline API provides declarative infrastructure for managing multi-environment deployments with manual promotion gates. It supports:

- **Centralized Pipeline Configuration**: Define tenant-specific release pipelines
- **Manual Promotion Gates**: Control artifact progression between environments
- **GitOps Integration**: All deployments happen through Git commits, never direct cluster access
- **Artifact Management**: Immutable artifacts with SHA-based tagging

## Architecture

### XReleasePipeline
Defines the overall release pipeline configuration for a tenant service.

**Key Features:**
- Environment progression (dev → staging → production)
- Promotion rules (manual/automatic gates)
- Artifact configuration (registry, retention)
- Testing configuration (preview mode for both PR and main branch)

### XPromotionGate
Manages manual approval workflows between environments.

**Key Features:**
- Manual approval requirements
- Timeout handling
- Approval tracking and audit trail
- Integration with pipeline orchestration

## Usage

### 1. Create Release Pipeline

```yaml
apiVersion: platform.zerotouch.dev/v1alpha1
kind: XReleasePipeline
metadata:
  name: my-service-pipeline
  namespace: platform-system
spec:
  tenant: "my-service"
  environments: ["dev", "staging", "production"]
  promotionRules:
    dev_to_staging: "manual"
    staging_to_production: "manual"
  artifactConfig:
    registry: "ghcr.io"
    retention_days: 30
  testing:
    validation_mode: "preview"
    bootstrap_mode: "preview"
```

### 2. Create Promotion Gate

```yaml
apiVersion: platform.zerotouch.dev/v1alpha1
kind: XPromotionGate
metadata:
  name: my-service-dev-to-staging
  namespace: platform-system
spec:
  tenant: "my-service"
  artifact_id: "ghcr.io/org/my-service:main-abc123"
  source_environment: "dev"
  target_environment: "staging"
  approval_required: true
  timeout_hours: 24
```

## Generated Resources

When you create an XReleasePipeline, Crossplane automatically provisions:

1. **ConfigMap**: Stores pipeline configuration for script consumption
2. **ExternalSecret**: Syncs credentials from AWS SSM Parameter Store
3. **ServiceAccount**: For pipeline script execution
4. **ClusterRole/ClusterRoleBinding**: Permissions for pipeline operations

When you create an XPromotionGate, Crossplane provisions:

1. **ConfigMap**: Stores gate status and configuration
2. **Job**: Handles timeout logic and gate lifecycle

## Integration with Platform Scripts

The platform scripts in `zerotouch-platform/scripts/release/` consume these resources:

1. **Configuration Discovery**: Scripts read ConfigMaps to get tenant settings
2. **Credential Access**: Scripts use ExternalSecrets for registry/GitHub access
3. **Gate Management**: Scripts create/update XPromotionGate resources
4. **Status Reporting**: Scripts update resource status for monitoring

## Security Model

- **Credentials**: Stored in AWS SSM Parameter Store, synced via ExternalSecrets
- **RBAC**: Minimal permissions for pipeline operations
- **Isolation**: Each tenant gets separate resources and permissions
- **Audit**: All operations logged and tracked through Kubernetes events

## Examples

See the `examples/` directory for:
- `deepagents-runtime-pipeline-claim.yaml` - Complete pipeline configuration
- `promotion-gate-example.yaml` - Manual promotion gate

## Testing

The API includes validation for:
- Required fields and valid enum values
- Environment progression logic
- Timeout and retention limits
- Tenant naming conventions

## Monitoring

Pipeline resources expose status through:
- Kubernetes conditions and events
- ConfigMap status updates
- Integration with platform observability stack