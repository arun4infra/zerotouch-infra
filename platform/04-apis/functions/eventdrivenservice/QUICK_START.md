# EventDrivenService Function - Quick Start

## One-Command Deployment

```bash
cd platform/04-apis/functions/eventdrivenservice && \
./build-and-push.sh && \
make install && \
kubectl apply -f ../../definitions/xeventdrivenservices.yaml && \
kubectl apply -f ../../compositions/event-driven-service-composition.yaml
```

## Step-by-Step

### 1. Build & Push (fetches credentials from AWS SSM)
```bash
./build-and-push.sh
```

### 2. Install Function
```bash
make install
```

### 3. Deploy XRD & Composition
```bash
kubectl apply -f ../../definitions/xeventdrivenservices.yaml
kubectl apply -f ../../compositions/event-driven-service-composition.yaml
```

### 4. Verify
```bash
kubectl get functions
kubectl get xrd
kubectl get composition
```

## Prerequisites

- ✅ AWS CLI configured
- ✅ Docker running
- ✅ kubectl configured
- ✅ SSM parameters exist:
  - `/zerotouch/prod/platform/ghcr/username`
  - `/zerotouch/prod/platform/ghcr/password`

## Test

```bash
kubectl apply -f - <<EOF
apiVersion: platform.bizmatters.io/v1alpha1
kind: EventDrivenService
metadata:
  name: test-service
  namespace: default
spec:
  image: nginx:latest
  size: small
  nats:
    stream: TEST_STREAM
    consumer: test-workers
EOF

# Check resources
kubectl get deployment,service,scaledobject,serviceaccount -l app.kubernetes.io/name=test-service

# Clean up
kubectl delete eventdrivenservice test-service
```

## Troubleshooting

```bash
# Function logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/function=function-eventdrivenservice

# Function status
kubectl get function function-eventdrivenservice -o yaml

# Composition status
kubectl describe composition event-driven-service
```

## Full Documentation

- **Deployment Guide:** `DEPLOYMENT_GUIDE.md`
- **Function README:** `README.md`
- **Build Verification:** `../../compositions/BUILD_VERIFICATION.md`
