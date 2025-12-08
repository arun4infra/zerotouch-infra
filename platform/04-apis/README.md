# EventDrivenService Platform API

A simplified Crossplane-based API for deploying NATS JetStream consumer services with KEDA autoscaling.

## Overview

The EventDrivenService API reduces deployment complexity from 212 lines of explicit Kubernetes manifests to approximately 30 lines of declarative YAML while maintaining full Zero-Touch compliance.

**Key Features:**
- ✅ No custom functions - uses standard Crossplane patches only
- ✅ Zero memory overhead - no additional pods required
- ✅ Hybrid Secret Sources - supports Crossplane, ESO, and manual secrets
- ✅ Simple API - pre-defined secret slots (up to 5 secrets)
- ✅ KEDA autoscaling - based on NATS queue depth
- ✅ Optional init containers - for database migrations

## Quick Start

### Prerequisites

1. NATS with JetStream deployed
2. KEDA installed
3. Crossplane with kubernetes provider
4. Secrets created (via Crossplane, ESO, or manually)

### Minimal Example

```yaml
apiVersion: platform.bizmatters.io/v1alpha1
kind: EventDrivenService
metadata:
  name: simple-worker
  namespace: workers
spec:
  image: ghcr.io/org/simple-worker:v1.0.0
  size: small
  nats:
    stream: SIMPLE_JOBS
    consumer: simple-workers
```

### Full Example (with secrets and init container)

```yaml
apiVersion: platform.bizmatters.io/v1alpha1
kind: EventDrivenService
metadata:
  name: agent-executor
  namespace: intelligence-deepagents
spec:
  image: ghcr.io/arun4infra/agent-executor:latest
  size: medium
  
  nats:
    stream: AGENT_EXECUTION
    consumer: agent-executor-workers
  
  # Secrets (envFrom - bulk mounting)
  secret1Name: agent-executor-db-conn      # Crossplane-generated
  secret2Name: agent-executor-cache-conn   # Crossplane-generated
  secret3Name: agent-executor-llm-keys     # ESO-synced
  
  imagePullSecrets:
    - name: ghcr-pull-secret
  
  initContainer:
    command: ["/bin/bash", "-c"]
    args: ["cd /app && ./scripts/ci/run-migrations.sh"]
```

## API Reference

### Spec Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `image` | string | Yes | Container image reference |
| `size` | enum | No | Resource size: `small`, `medium`, `large` (default: `medium`) |
| `nats.url` | string | No | NATS server URL (default: `nats://nats.nats.svc:4222`) |
| `nats.stream` | string | Yes | JetStream stream name |
| `nats.consumer` | string | Yes | Consumer group name |
| `secret1Name` | string | No | First secret name (envFrom) |
| `secret2Name` | string | No | Second secret name (envFrom) |
| `secret3Name` | string | No | Third secret name (envFrom) |
| `secret4Name` | string | No | Fourth secret name (envFrom) |
| `secret5Name` | string | No | Fifth secret name (envFrom) |
| `imagePullSecrets` | array | No | Image pull secret names |
| `initContainer.command` | array | No | Init container command |
| `initContainer.args` | array | No | Init container arguments |

### Resource Sizing

| Size | CPU Request | CPU Limit | Memory Request | Memory Limit |
|------|-------------|-----------|----------------|--------------|
| `small` | 250m | 1000m | 512Mi | 2Gi |
| `medium` | 500m | 2000m | 1Gi | 4Gi |
| `large` | 1000m | 4000m | 2Gi | 8Gi |

## Hybrid Secret Sources

The API supports secrets from multiple sources without consolidation:

### Crossplane-Generated Secrets

```yaml
# PostgresInstance creates secret automatically
apiVersion: database.bizmatters.io/v1alpha1
kind: PostgresInstance
metadata:
  name: my-service-db
spec:
  writeConnectionSecretToRef:
    name: my-service-db-conn  # ← Reference this in EventDrivenService
    namespace: my-namespace
```

```yaml
# Reference in EventDrivenService
spec:
  secret1Name: my-service-db-conn
```

### ESO-Synced Secrets

```yaml
# ExternalSecret syncs from AWS SSM
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-service-llm-keys
spec:
  secretStoreRef:
    name: aws-parameter-store
  target:
    name: my-service-llm-keys  # ← Reference this in EventDrivenService
  data:
    - secretKey: OPENAI_API_KEY
      remoteRef:
        key: /app/openai_api_key
```

```yaml
# Reference in EventDrivenService
spec:
  secret3Name: my-service-llm-keys
```

## Secret Mounting (envFrom)

All secrets are mounted using `envFrom` (bulk mounting). This means:
- ✅ All keys in the secret become environment variables
- ✅ Key names must match desired environment variable names
- ✅ Simple and predictable

**Example:** If `my-service-db-conn` contains:
```yaml
data:
  POSTGRES_HOST: cG9zdGdyZXMuc3Zj
  POSTGRES_PORT: NTQzMg==
  POSTGRES_DB: bXlkYg==
```

Then the container will have these environment variables:
- `POSTGRES_HOST=postgres.svc`
- `POSTGRES_PORT=5432`
- `POSTGRES_DB=mydb`

## Resources Created

The composition creates 4 Kubernetes resources:

1. **Deployment** - Main application with optional init container
2. **Service** - ClusterIP service on port 8080
3. **ScaledObject** - KEDA autoscaler (1-10 replicas)
4. **ServiceAccount** - Pod identity

## KEDA Autoscaling

Automatic scaling based on NATS queue depth:
- **Min replicas:** 1
- **Max replicas:** 10
- **Lag threshold:** 5 messages
- **Monitoring endpoint:** `nats-headless.nats.svc.cluster.local:8222`

## Health Probes

Services must implement these HTTP endpoints:

- **Liveness:** `GET /health` on port 8080
- **Readiness:** `GET /ready` on port 8080

## Troubleshooting

### Pod not starting - CreateContainerConfigError

**Cause:** Referenced secret doesn't exist

**Solution:**
```bash
# Check if secret exists
kubectl get secret <secret-name> -n <namespace>

# Check Crossplane claim status
kubectl get postgresinstance <name> -n <namespace>
```

### Pod not starting - ImagePullBackOff

**Cause:** Image pull secret missing or invalid

**Solution:**
```bash
# Check image pull secret
kubectl get secret <image-pull-secret> -n <namespace>

# Verify secret is referenced in claim
kubectl get eventdrivenservice <name> -o yaml | grep imagePullSecrets
```

### KEDA not scaling

**Cause:** NATS stream doesn't exist or consumer mismatch

**Solution:**
```bash
# Check NATS stream
kubectl exec -n nats nats-0 -c nats-box -- nats stream info <stream-name>

# Check ScaledObject status
kubectl describe scaledobject <name>-scaler
```

## Migration from Direct Manifests

**Before (84 lines):**
```yaml
# Deployment + Service + ScaledObject + ServiceAccount
# Explicit Kubernetes manifests
```

**After (22 lines):**
```yaml
apiVersion: platform.bizmatters.io/v1alpha1
kind: EventDrivenService
metadata:
  name: my-service
spec:
  image: ghcr.io/org/my-service:v1.0.0
  size: medium
  nats:
    stream: MY_STREAM
    consumer: my-workers
  secret1Name: my-service-db-conn
  secret2Name: my-service-cache-conn
  secret3Name: my-service-llm-keys
  imagePullSecrets:
    - name: ghcr-pull-secret
  initContainer:
    command: ["/bin/bash", "-c"]
    args: ["./run-migrations.sh"]
```

**Savings:** 70% reduction in deployment complexity

## Examples

See `examples/` directory:
- `minimal-claim.yaml` - Simplest possible claim
- `agent-executor-claim.yaml` - Full-featured reference implementation

## Architecture

This API uses:
- **Crossplane XRD** - Defines the API schema
- **Crossplane Composition** - Provisions Kubernetes resources
- **Standard patches only** - No custom functions required
- **Zero-Touch principles** - Accepts Crossplane/ESO-generated secrets as-is
