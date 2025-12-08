# EventDrivenService Function - Deployment Guide

This guide walks through building, pushing, and deploying the EventDrivenService composition function to your Crossplane-enabled cluster.

## Prerequisites

### 1. Local Development Tools
- ✅ Docker installed and running
- ✅ AWS CLI installed and configured
- ✅ kubectl configured for your cluster
- ✅ Go 1.21+ (for local builds)

### 2. AWS SSM Parameters

The build script fetches GHCR credentials from AWS SSM Parameter Store. Ensure these parameters exist:

```bash
# Check if parameters exist
aws ssm get-parameter --name /zerotouch/prod/platform/ghcr/username --region ap-south-1
aws ssm get-parameter --name /zerotouch/prod/platform/ghcr/password --with-decryption --region ap-south-1
```

If they don't exist, create them:

```bash
# Create GHCR username parameter
aws ssm put-parameter \
  --name '/zerotouch/prod/platform/ghcr/username' \
  --value 'your-github-username' \
  --type SecureString \
  --region ap-south-1

# Create GHCR password/token parameter
aws ssm put-parameter \
  --name '/zerotouch/prod/platform/ghcr/password' \
  --value 'your-github-personal-access-token' \
  --type SecureString \
  --region ap-south-1
```

**GitHub Token Permissions Required:**
- `write:packages` - Push container images
- `read:packages` - Pull container images
- `delete:packages` - Delete container images (optional)

### 3. Cluster Prerequisites

Verify Crossplane is installed and ready:

```bash
# Check Crossplane installation
kubectl get pods -n crossplane-system

# Verify function-patch-and-transform is available
kubectl get functions
```

---

## Deployment Steps

### Step 1: Build and Push Function Image

The `build-and-push.sh` script handles everything:
- Fetches GHCR credentials from AWS SSM
- Builds the Docker image
- Logs in to GHCR
- Pushes the image
- Logs out (security best practice)

```bash
cd platform/04-apis/functions/eventdrivenservice

# Option A: Use the automated script (recommended)
./build-and-push.sh

# Option B: Use Make
make push

# Option C: Build specific version
VERSION=v0.2.0 ./build-and-push.sh
```

**Expected Output:**
```
╔══════════════════════════════════════════════════════════════╗
║   EventDrivenService Function - Build & Push                ║
╚══════════════════════════════════════════════════════════════╝

Checking prerequisites...
✓ Docker installed
✓ AWS CLI installed
✓ AWS credentials configured

Fetching GHCR credentials from AWS SSM...
✓ GHCR credentials fetched from SSM
✓ Username: arun4infra

Building Docker image...
Image: ghcr.io/arun4infra/function-eventdrivenservice:v0.1.0

✓ Docker image built successfully

Logging in to GHCR...
✓ Logged in to ghcr.io

Pushing image to GHCR...
✓ Image pushed successfully

╔══════════════════════════════════════════════════════════════╗
║   Build & Push Complete                                     ║
╚══════════════════════════════════════════════════════════════╝

✓ Function image available at: ghcr.io/arun4infra/function-eventdrivenservice:v0.1.0
```

### Step 2: Install Function in Cluster

Install the Crossplane Function package:

```bash
# Option A: Use Make
make install

# Option B: Manual installation
kubectl apply -f - <<EOF
apiVersion: pkg.crossplane.io/v1beta1
kind: Function
metadata:
  name: function-eventdrivenservice
spec:
  package: ghcr.io/arun4infra/function-eventdrivenservice:v0.1.0
EOF
```

### Step 3: Verify Function Installation

```bash
# Check function status
kubectl get functions
kubectl get function function-eventdrivenservice -o yaml

# Check function pod
kubectl get pods -n crossplane-system | grep function-eventdrivenservice

# Check function logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/function=function-eventdrivenservice
```

**Expected Output:**
```
NAME                          INSTALLED   HEALTHY   PACKAGE                                                    AGE
function-eventdrivenservice   True        True      ghcr.io/arun4infra/function-eventdrivenservice:v0.1.0     30s
```

### Step 4: Deploy XRD and Composition

```bash
# Deploy XRD
kubectl apply -f ../../definitions/xeventdrivenservices.yaml

# Verify XRD installed
kubectl get xrd xeventdrivenservices.platform.bizmatters.io

# Deploy Composition
kubectl apply -f ../../compositions/event-driven-service-composition.yaml

# Verify Composition
kubectl get composition event-driven-service
```

### Step 5: Test with Example Claim

```bash
# Create a minimal test claim
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

# Check claim status
kubectl get eventdrivenservice test-service -o yaml

# Check created resources
kubectl get deployment test-service
kubectl get service test-service
kubectl get scaledobject test-service-scaler
kubectl get serviceaccount test-service

# Clean up test
kubectl delete eventdrivenservice test-service
```

---

## Troubleshooting

### Issue: AWS SSM Parameters Not Found

**Error:**
```
✗ Failed to fetch GHCR username from SSM
Parameter: /zerotouch/prod/platform/ghcr/username
```

**Solution:**
```bash
# Verify parameters exist
aws ssm describe-parameters --region ap-south-1 | grep ghcr

# Create missing parameters (see Prerequisites section)
```

### Issue: Docker Build Fails

**Error:**
```
✗ Docker build failed
```

**Solution:**
```bash
# Check Docker is running
docker ps

# Check Dockerfile syntax
docker build --no-cache -t test .

# Check Go dependencies
go mod tidy
go mod download
```

### Issue: Function Pod Not Starting

**Error:**
```
kubectl get pods -n crossplane-system | grep function-eventdrivenservice
function-eventdrivenservice-xxx   0/1     ImagePullBackOff
```

**Solution:**
```bash
# Check image pull secret exists
kubectl get secret -n crossplane-system | grep ghcr

# Verify image exists in registry
docker pull ghcr.io/arun4infra/function-eventdrivenservice:v0.1.0

# Check function package status
kubectl describe function function-eventdrivenservice
```

### Issue: Composition Not Using Function

**Error:**
Composition creates resources but secretRefs not processed

**Solution:**
```bash
# Check function is referenced in composition
kubectl get composition event-driven-service -o yaml | grep function-eventdrivenservice

# Check function logs for errors
kubectl logs -n crossplane-system -l pkg.crossplane.io/function=function-eventdrivenservice --tail=50

# Verify pipeline mode is enabled
kubectl get composition event-driven-service -o yaml | grep "mode: Pipeline"
```

---

## Updating the Function

### Update Code and Rebuild

```bash
# 1. Make code changes to main.go

# 2. Increment version
export VERSION=v0.2.0

# 3. Build and push
./build-and-push.sh

# 4. Update function package in cluster
kubectl patch function function-eventdrivenservice \
  --type merge \
  -p '{"spec":{"package":"ghcr.io/arun4infra/function-eventdrivenservice:v0.2.0"}}'

# 5. Wait for rollout
kubectl rollout status deployment -n crossplane-system \
  -l pkg.crossplane.io/function=function-eventdrivenservice

# 6. Verify new version
kubectl get function function-eventdrivenservice -o yaml | grep package
```

---

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Build and Push Function

on:
  push:
    branches: [main]
    paths:
      - 'platform/04-apis/functions/eventdrivenservice/**'

jobs:
  build-push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ap-south-1
      
      - name: Build and push function
        run: |
          cd platform/04-apis/functions/eventdrivenservice
          ./build-and-push.sh
```

---

## Security Best Practices

1. **Credentials Management**
   - ✅ Credentials stored in AWS SSM (encrypted)
   - ✅ Script logs out after push
   - ✅ No credentials in code or logs

2. **Image Security**
   - ✅ Use distroless base image
   - ✅ Run as non-root user (65532)
   - ✅ Scan images for vulnerabilities

3. **Access Control**
   - ✅ Limit AWS SSM parameter access via IAM
   - ✅ Use GitHub PAT with minimal permissions
   - ✅ Rotate credentials regularly

---

## Monitoring

### Function Health

```bash
# Check function pod health
kubectl get pods -n crossplane-system -l pkg.crossplane.io/function=function-eventdrivenservice

# View function logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/function=function-eventdrivenservice --tail=100 -f

# Check function metrics (if Prometheus installed)
kubectl port-forward -n crossplane-system svc/function-eventdrivenservice 9090:9090
```

### Composition Usage

```bash
# List all EventDrivenService claims
kubectl get eventdrivenservice -A

# Check composition status
kubectl get composition event-driven-service -o yaml

# View recent events
kubectl get events -n crossplane-system --sort-by='.lastTimestamp' | grep function
```

---

## Support

For issues or questions:
1. Check function logs: `kubectl logs -n crossplane-system -l pkg.crossplane.io/function=function-eventdrivenservice`
2. Review composition: `kubectl describe composition event-driven-service`
3. Check claim status: `kubectl describe eventdrivenservice <name>`
4. Refer to Crossplane docs: https://docs.crossplane.io/latest/concepts/composition-functions/
