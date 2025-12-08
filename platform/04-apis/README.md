# Platform APIs Layer (04-apis)

## Overview

The 04-apis layer provides reusable platform APIs built on Crossplane that enable declarative deployment of common service patterns. These APIs abstract away Kubernetes complexity while maintaining Zero-Touch principles and GitOps compatibility.

## Purpose

This layer enables platform consumers to deploy services using high-level declarative APIs instead of writing explicit Kubernetes manifests. Each API is implemented as a Crossplane Composite Resource Definition (XRD) with one or more Compositions that provision the underlying Kubernetes resources.

## Architecture

```
platform/04-apis/
├── definitions/          # Crossplane XRDs (API contracts)
├── compositions/         # Crossplane Compositions (implementation templates)
├── examples/            # Example claims for each API
├── schemas/             # Published JSON schemas for validation
└── tests/               # Validation and integration tests
```

## Available APIs

### EventDrivenService API

**Status:** In Development

**Purpose:** Deploy NATS JetStream consumer services with KEDA autoscaling

**Use Case:** Event-driven worker services that process messages from NATS queues

**Key Features:**
- Declarative deployment with ~30 lines of YAML (vs 212 lines of direct manifests)
- Automatic KEDA autoscaling based on NATS queue depth
- Hybrid secret mounting (Crossplane + ESO secrets)
- Optional init containers for database migrations
- Size-based resource allocation (small/medium/large)
- Built-in health and readiness probes

**Example:**
```yaml
apiVersion: platform.bizmatters.io/v1alpha1
kind: EventDrivenService
metadata:
  name: my-worker
  namespace: my-namespace
spec:
  image: ghcr.io/org/my-worker:v1.0.0
  size: medium
  nats:
    stream: MY_JOBS
    consumer: my-workers
```

**Documentation:** See [EventDrivenService API Documentation](./docs/eventdrivenservice.md) (coming soon)

## Deployment

### ArgoCD Configuration

The 04-apis layer is deployed as an ArgoCD Application with:
- **Sync Wave:** 1 (deploys after foundation layer)
- **Automated Sync:** Enabled with prune and selfHeal
- **Source:** `platform/04-apis` directory in zerotouch-platform repository

### Prerequisites

Before using APIs in this layer, ensure:
1. Foundation layer (01-foundation) is deployed and healthy
2. Crossplane is installed with provider-kubernetes configured
3. Required infrastructure (NATS, KEDA, etc.) is deployed

### Verification

Verify the 04-apis layer is deployed:
```bash
# Check ArgoCD Application status
kubectl get application apis -n argocd

# Verify XRDs are installed
kubectl get xrd

# Verify Compositions are available
kubectl get composition
```

## Usage

### Creating a Claim

1. Choose the appropriate API for your use case
2. Create a claim YAML file following the API schema
3. Validate the claim against the published JSON schema (optional but recommended)
4. Commit the claim to your application repository
5. ArgoCD will sync and provision the resources

### Validation

Validate claims before deployment:
```bash
# Validate a claim against the schema
./scripts/validate-claim.sh path/to/my-claim.yaml
```

### Monitoring

Check claim status:
```bash
# View claim status
kubectl get <api-kind> <claim-name> -n <namespace> -o yaml

# View provisioned resources
kubectl describe <api-kind> <claim-name> -n <namespace>
```

## Development

### Adding a New API

1. Create XRD in `definitions/`
2. Create Composition in `compositions/`
3. Add example claims in `examples/`
4. Publish JSON schema to `schemas/`
5. Add validation tests in `tests/`
6. Update this README with API documentation

### Testing

Run validation tests:
```bash
# Schema validation tests
./platform/04-apis/tests/schema-validation.test.sh

# Composition tests
./platform/04-apis/tests/composition.test.sh
```

## Design Principles

### Zero-Touch Compliance

All APIs in this layer follow Zero-Touch principles:
- **Crash-only recovery:** All state in Git, no manual intervention required
- **Declarative:** Resources defined as desired state, not imperative commands
- **GitOps-native:** Changes flow through Git commits and ArgoCD sync
- **Self-healing:** ArgoCD automatically corrects drift from desired state

### Separation of Concerns

Platform APIs focus on deployment patterns, not infrastructure provisioning:
- **Infrastructure:** Databases, caches, message queues (separate Crossplane APIs)
- **Secrets:** Managed by Crossplane and ESO (not created by platform APIs)
- **Networking:** Ingress, service mesh (separate layer)
- **Observability:** Metrics, logging, tracing (application responsibility)

### Hybrid Secret Approach

Platform APIs support multiple secret sources without consolidation:
- **Crossplane-generated:** Database credentials, cache credentials
- **ESO-synced:** Application secrets from AWS SSM Parameter Store
- **Manual:** Kubernetes secrets created directly (not recommended)

This approach respects the Zero-Touch principle by not requiring manual secret consolidation.

## Troubleshooting

### Common Issues

**XRD not found:**
- Verify 04-apis Application is synced: `kubectl get application apis -n argocd`
- Check for errors: `kubectl describe application apis -n argocd`

**Composition not working:**
- Verify Crossplane is healthy: `kubectl get pods -n crossplane-system`
- Check Composition logs: `kubectl logs -n crossplane-system -l app=crossplane`

**Claim stuck in pending:**
- Check claim status: `kubectl describe <api-kind> <claim-name>`
- Verify referenced secrets exist
- Check Crossplane provider configuration

## References

- [Crossplane Documentation](https://docs.crossplane.io/)
- [ArgoCD Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [KEDA Documentation](https://keda.sh/)
- [NATS JetStream](https://docs.nats.io/nats-concepts/jetstream)

## Metadata

**Layer:** 04-apis  
**Sync Wave:** 1  
**Dependencies:** 01-foundation (Crossplane, provider-kubernetes)  
**Status:** Active Development  
**Last Updated:** 2025-12-08
