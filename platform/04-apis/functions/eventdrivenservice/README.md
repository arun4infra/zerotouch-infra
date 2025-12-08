# EventDrivenService Composition Function

This Crossplane composition function handles dynamic secret mounting and optional init container configuration for the EventDrivenService platform API.

## Purpose

The patch-and-transform function has limitations when working with dynamic arrays. This custom function solves that by:

1. **Building dynamic `env` arrays** from `spec.secretRefs` with individual key mappings
2. **Building dynamic `envFrom` arrays** from `spec.secretRefs` with bulk mounting
3. **Creating optional init containers** with the same secret access as the main container

## How It Works

### Input (from EventDrivenService claim)

```yaml
apiVersion: platform.bizmatters.io/v1alpha1
kind: EventDrivenService
spec:
  image: ghcr.io/org/my-service:v1.0.0
  nats:
    url: nats://nats.nats.svc:4222
    stream: MY_STREAM
    consumer: my-workers
  secretRefs:
    - name: my-db-conn
      env:
        - secretKey: endpoint
          envName: POSTGRES_HOST
        - secretKey: port
          envName: POSTGRES_PORT
    - name: my-llm-keys
      envFrom: true
  initContainer:
    command: ["/bin/bash", "-c"]
    args: ["./scripts/run-migrations.sh"]
```

### Processing Logic

1. **Extract NATS configuration** → Build base env vars:
   ```go
   env:
     - name: NATS_URL
       value: nats://nats.nats.svc:4222
     - name: NATS_STREAM_NAME
       value: MY_STREAM
     - name: NATS_CONSUMER_GROUP
       value: my-workers
   ```

2. **Process secretRefs with `env` field** → Add secretKeyRef entries:
   ```go
   env:
     - name: POSTGRES_HOST
       valueFrom:
         secretKeyRef:
           name: my-db-conn
           key: endpoint
     - name: POSTGRES_PORT
       valueFrom:
         secretKeyRef:
           name: my-db-conn
           key: port
   ```

3. **Process secretRefs with `envFrom: true`** → Add envFrom entries:
   ```go
   envFrom:
     - secretRef:
         name: my-llm-keys
   ```

4. **If initContainer specified** → Create init container with same env/envFrom:
   ```go
   initContainers:
     - name: run-migrations
       image: ghcr.io/org/my-service:v1.0.0  # Same as main
       command: ["/bin/bash", "-c"]
       args: ["./scripts/run-migrations.sh"]
       env: [...]  # Same as main container
       envFrom: [...]  # Same as main container
   ```

### Output (to Deployment manifest)

The function updates the Deployment resource in the desired composed resources with the fully constructed env, envFrom, and optional initContainers arrays.

## Building the Function

```bash
# Build the container image
docker build -t ghcr.io/arun4infra/function-eventdrivenservice:v0.1.0 \
  platform/04-apis/functions/eventdrivenservice/

# Push to registry
docker push ghcr.io/arun4infra/function-eventdrivenservice:v0.1.0

# Build the Crossplane package
kubectl crossplane build function \
  -f platform/04-apis/functions/eventdrivenservice/package.yaml \
  -o function-eventdrivenservice.xpkg

# Push the package
kubectl crossplane push function function-eventdrivenservice.xpkg \
  ghcr.io/arun4infra/function-eventdrivenservice:v0.1.0
```

## Installing the Function

```bash
# Install the function in the cluster
kubectl apply -f - <<EOF
apiVersion: pkg.crossplane.io/v1beta1
kind: Function
metadata:
  name: function-eventdrivenservice
spec:
  package: ghcr.io/arun4infra/function-eventdrivenservice:v0.1.0
EOF

# Verify installation
kubectl get functions
kubectl get pods -n crossplane-system | grep function-eventdrivenservice
```

## Testing

```bash
# Apply a test claim
kubectl apply -f platform/04-apis/examples/full-claim.yaml

# Check the generated Deployment
kubectl get deployment agent-executor -n intelligence-deepagents -o yaml

# Verify env vars are correctly built
kubectl get deployment agent-executor -n intelligence-deepagents \
  -o jsonpath='{.spec.template.spec.containers[0].env}' | jq

# Verify envFrom is correctly built
kubectl get deployment agent-executor -n intelligence-deepagents \
  -o jsonpath='{.spec.template.spec.containers[0].envFrom}' | jq

# Verify init container if specified
kubectl get deployment agent-executor -n intelligence-deepagents \
  -o jsonpath='{.spec.template.spec.initContainers}' | jq
```

## Development

### Prerequisites

- Go 1.21+
- Docker
- kubectl with Crossplane installed
- Access to container registry (GHCR)

### Local Development

```bash
cd platform/04-apis/functions/eventdrivenservice

# Download dependencies
go mod download

# Run tests
go test ./...

# Build locally
go build -o function .

# Test with sample input
./function < test-input.json
```

### Debugging

```bash
# Check function logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/function=function-eventdrivenservice

# Check composition status
kubectl get composition event-driven-service -o yaml

# Check claim status
kubectl get eventdrivenservice my-service -o yaml
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ EventDrivenService Claim (XR)                               │
│ spec:                                                        │
│   secretRefs: [...]                                         │
│   initContainer: {...}                                      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ Composition Pipeline                                         │
│                                                              │
│ Step 1: patch-and-transform                                 │
│   - Create base resources (SA, Deployment, Service, KEDA)  │
│   - Patch static fields (image, size, labels)              │
│                                                              │
│ Step 2: function-eventdrivenservice (THIS FUNCTION)        │
│   - Read spec.secretRefs from XR                           │
│   - Build env array (NATS + secretKeyRef entries)          │
│   - Build envFrom array (secretRef entries)                │
│   - If spec.initContainer exists, create initContainers    │
│   - Update Deployment manifest in desired resources        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ Kubernetes Resources                                         │
│ - ServiceAccount                                            │
│ - Deployment (with env, envFrom, initContainers)           │
│ - Service                                                    │
│ - ScaledObject                                              │
└─────────────────────────────────────────────────────────────┘
```

## Troubleshooting

### Function not found

```bash
# Check if function is installed
kubectl get functions

# Check function pod status
kubectl get pods -n crossplane-system | grep function-eventdrivenservice

# Check function logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/function=function-eventdrivenservice
```

### Composition errors

```bash
# Check composition status
kubectl describe composition event-driven-service

# Check XR status
kubectl get xeventdrivenservice -A

# Check claim status
kubectl describe eventdrivenservice my-service -n my-namespace
```

### Env vars not appearing

1. Check function logs for errors
2. Verify secretRefs structure in claim matches expected format
3. Check Deployment manifest: `kubectl get deployment -o yaml`
4. Verify secrets exist: `kubectl get secrets`

## References

- [Crossplane Composition Functions](https://docs.crossplane.io/latest/concepts/composition-functions/)
- [Function SDK Go](https://github.com/crossplane/function-sdk-go)
- [Writing Composition Functions](https://docs.crossplane.io/knowledge-base/guides/write-a-composition-function-in-go/)
