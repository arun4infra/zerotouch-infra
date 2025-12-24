#!/bin/bash
set -euo pipefail

# ==============================================================================
# CI Deploy Script for ide-orchestrator
# ==============================================================================
# Purpose: GitOps service deployment automation
# 
# IMPORTANT: Preview vs Production Namespace Handling
# - Production: Namespaces created by tenant-infrastructure (ArgoCD app)  
# - Preview: Namespaces created by this CI script (mocks landing zones)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Default values
ENVIRONMENT="${1:-ci}"
IMAGE_TAG="${2:-latest}"
SERVICE_NAME="${SERVICE_NAME:-ide-orchestrator}"  # Can be overridden by environment variable
NAMESPACE="${NAMESPACE:-intelligence-orchestrator}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-300}"

echo "🚀 Deploying ${SERVICE_NAME} to ${ENVIRONMENT} environment..."

cd "${PROJECT_ROOT}"

# Validate environment
case "${ENVIRONMENT}" in
    ci|staging|production)
        echo "✅ Valid environment: ${ENVIRONMENT}"
        ;;
    *)
        echo "❌ Invalid environment: ${ENVIRONMENT}. Must be ci, staging, or production"
        exit 1
        ;;
esac

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed or not in PATH"
    exit 1
fi

# Check cluster connectivity
echo "🔍 Checking cluster connectivity..."
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Cannot connect to Kubernetes cluster"
    exit 1
fi

# Mock Landing Zone (Preview Mode Only)
# In Production, tenant-infrastructure creates namespaces
# In Preview, CI must simulate this behavior
echo "📁 Setting up landing zone for preview mode..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
echo "✅ Mock landing zone '${NAMESPACE}' created"

# Apply platform claims and manifests
echo "📋 Applying platform claims..."
if [[ -d "platform/claims/${NAMESPACE}" ]]; then
    # Apply platform claims for the namespace
    kubectl apply -f "platform/claims/${NAMESPACE}/" -n "${NAMESPACE}"
    echo "✅ Platform claims applied"
elif [[ -d "k8s/${ENVIRONMENT}" ]]; then
    # Environment-specific manifests (fallback)
    kubectl apply -f "k8s/${ENVIRONMENT}/" -n "${NAMESPACE}"
elif [[ -d "k8s/base" ]]; then
    # Base manifests with kustomization (fallback)
    kubectl apply -k "k8s/base" -n "${NAMESPACE}"
else
    echo "❌ No platform claims found in platform/claims/${NAMESPACE} or k8s manifests"
    exit 1
fi

# Update image tag if provided
if [[ "${IMAGE_TAG}" != "latest" ]]; then
    echo "🏷️  Updating image tag to ${IMAGE_TAG}..."
    kubectl set image deployment/${SERVICE_NAME} \
        ${SERVICE_NAME}="${SERVICE_NAME}:${IMAGE_TAG}" \
        -n "${NAMESPACE}"
fi

# Wait for deployment to be ready
echo "⏳ Waiting for deployment to be ready..."
kubectl rollout status deployment/${SERVICE_NAME} \
    -n "${NAMESPACE}" \
    --timeout="${WAIT_TIMEOUT}s"

# Verify deployment
echo "🔍 Verifying deployment..."
READY_REPLICAS=$(kubectl get deployment ${SERVICE_NAME} -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}')
DESIRED_REPLICAS=$(kubectl get deployment ${SERVICE_NAME} -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')

if [[ "${READY_REPLICAS}" == "${DESIRED_REPLICAS}" ]]; then
    echo "✅ Deployment successful: ${READY_REPLICAS}/${DESIRED_REPLICAS} replicas ready"
else
    echo "❌ Deployment failed: ${READY_REPLICAS}/${DESIRED_REPLICAS} replicas ready"
    exit 1
fi

# Show service endpoints
echo "🌐 Service endpoints:"
kubectl get services -n "${NAMESPACE}" -l app=${SERVICE_NAME}

echo "🎉 Deployment completed successfully!"