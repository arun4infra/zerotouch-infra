# EventDrivenService Composition Implementation Notes

## Current Implementation Status

### ✅ Fully Implemented Features

1. **ServiceAccount** - Creates a dedicated ServiceAccount for the service
2. **Deployment** - Creates a Deployment with:
   - Configurable image
   - Size-based resource allocation (small/medium/large)
   - Security context (Pod Security Standards compliant)
   - Health and readiness probes
   - NATS environment variables (NATS_URL, NATS_STREAM_NAME, NATS_CONSUMER_GROUP)
   - **Dynamic secret mounting** via custom composition function
   - **Optional init container** via custom composition function
3. **Service** - Creates a ClusterIP Service exposing port 8080
4. **KEDA ScaledObject** - Creates autoscaling based on NATS queue depth
   - Uses `nats-headless` endpoint (critical fix)
   - Scales 1-10 replicas based on lag threshold
5. **Custom Composition Function** - Handles complex logic:
   - Builds dynamic env arrays from secretRefs
   - Builds dynamic envFrom arrays from secretRefs
   - Creates optional init containers with same secret access

## Implementation Approach

We use a **two-step pipeline** approach with Crossplane Composition Functions:

### Step 1: patch-and-transform
Handles static field patching:
- Resource creation (ServiceAccount, Deployment, Service, ScaledObject)
- Image, size, labels, NATS env vars
- ImagePullSecrets

### Step 2: function-eventdrivenservice (Custom Function)
Handles dynamic array building:
- Processes `spec.secretRefs` array
- Builds `env` array with secretKeyRef entries
- Builds `envFrom` array with secretRef entries
- Creates optional `initContainers` array
- Updates Deployment manifest with fully constructed arrays

## Why Composition Functions?

The patch-and-transform function has limitations with dynamic arrays. Crossplane Composition Functions (introduced in 1.14+) are the official solution for complex logic.

**Benefits:**
- ✅ Official Crossplane pattern (not a workaround)
- ✅ Full control over manifest generation
- ✅ Can handle complex conditional logic
- ✅ Reusable across compositions
- ✅ Aligns with "Pipeline mode" in design doc

## Custom Function Details

**Location:** `platform/04-apis/functions/eventdrivenservice/`

**Language:** Go (using Crossplane Function SDK)

**Container Image:** `ghcr.io/arun4infra/function-eventdrivenservice:v0.1.0`

**Processing Logic:**
1. Extract `spec.secretRefs` from composite resource
2. Build base env vars (NATS_URL, NATS_STREAM_NAME, NATS_CONSUMER_GROUP)
3. For each secretRef with `env` field → Add secretKeyRef entries
4. For each secretRef with `envFrom: true` → Add secretRef entries
5. If `spec.initContainer` exists → Create init container with same env/envFrom
6. Update Deployment resource in desired composed resources

See `platform/04-apis/functions/eventdrivenservice/README.md` for full documentation.

## Deployment Steps

### 1. Build and Push Function

```bash
# Build container image
docker build -t ghcr.io/arun4infra/function-eventdrivenservice:v0.1.0 \
  platform/04-apis/functions/eventdrivenservice/

# Push to registry
docker push ghcr.io/arun4infra/function-eventdrivenservice:v0.1.0
```

### 2. Install Function in Cluster

```bash
kubectl apply -f - <<EOF
apiVersion: pkg.crossplane.io/v1beta1
kind: Function
metadata:
  name: function-eventdrivenservice
spec:
  package: ghcr.io/arun4infra/function-eventdrivenservice:v0.1.0
EOF
```

### 3. Verify Function Installation

```bash
kubectl get functions
kubectl get pods -n crossplane-system | grep function-eventdrivenservice
```

### 4. Deploy Composition

The composition at `platform/04-apis/compositions/event-driven-service-composition.yaml` references the function in its pipeline.

## Testing

The implementation can now be fully tested with:
- ✅ Minimal claims (image + NATS only)
- ✅ Size variations (small/medium/large)
- ✅ ImagePullSecrets
- ✅ Secret mounting (individual keys + bulk envFrom)
- ✅ Init containers with secret access

## Next Steps

1. **Build and push function** - Create container image and push to GHCR
2. **Install function** - Deploy to cluster via Crossplane package
3. **Test with examples** - Validate with minimal, full, and agent-executor claims
4. **Document in API README** - Add function installation to platform documentation

