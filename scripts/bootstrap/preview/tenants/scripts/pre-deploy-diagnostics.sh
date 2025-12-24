#!/bin/bash
set -euo pipefail

# Infrastructure Readiness Validation Before Deployment
# Validates that all required infrastructure is ready before deploying

NAMESPACE="${NAMESPACE:-intelligence-orchestrator}"

# Check if running in preview mode (Kind cluster)
IS_PREVIEW_MODE=false
if kubectl get nodes -o name 2>/dev/null | grep -q "zerotouch-preview"; then
    IS_PREVIEW_MODE=true
fi

if [ "$IS_PREVIEW_MODE" = true ]; then
    # Preview mode: Only check core platform components
    REQUIRED_NAMESPACES=(
        "cnpg-system"
        "external-secrets"
    )
    echo "🔍 Running pre-deployment diagnostics (Preview Mode)..."
    echo "ℹ️  Application namespaces will be created by deploy script"
else
    # Production mode: Check all namespaces (should exist via tenant-infrastructure)
    REQUIRED_NAMESPACES=(
        "intelligence-orchestrator"
        "intelligence-deepagents"
        "cnpg-system"
        "external-secrets"
    )
    echo "🔍 Running pre-deployment diagnostics (Production Mode)..."
fi

# Check kubectl connectivity
echo "🔗 Checking Kubernetes cluster connectivity..."
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Cannot connect to Kubernetes cluster"
    exit 1
fi
echo "✅ Kubernetes cluster is accessible"

# Check required namespaces
echo "📁 Checking required namespaces..."
for ns in "${REQUIRED_NAMESPACES[@]}"; do
    if kubectl get namespace "${ns}" &>/dev/null; then
        echo "✅ Namespace ${ns} exists"
    else
        if [ "$IS_PREVIEW_MODE" = true ]; then
            echo "⚠️  Namespace ${ns} does not exist (will be created by platform/deploy script)"
        else
            echo "❌ Namespace ${ns} does not exist"
            exit 1
        fi
    fi
done

# Check CNPG operator
echo "🗄️  Checking CloudNative PostgreSQL operator..."
if kubectl get deployment cnpg-cloudnative-pg -n cnpg-system &>/dev/null; then
    echo "✅ CNPG operator is deployed"
    
    # Check if operator is ready
    if kubectl get deployment cnpg-cloudnative-pg -n cnpg-system -o jsonpath='{.status.readyReplicas}' | grep -q "1"; then
        echo "✅ CNPG operator is ready"
    else
        echo "❌ CNPG operator is not ready"
        exit 1
    fi
else
    echo "❌ CNPG operator is not deployed"
    exit 1
fi

# Check External Secrets operator
echo "🔐 Checking External Secrets operator..."
if kubectl get deployment external-secrets -n external-secrets &>/dev/null; then
    echo "✅ External Secrets operator is deployed"
    
    # Check if operator is ready
    if kubectl get deployment external-secrets -n external-secrets -o jsonpath='{.status.readyReplicas}' | grep -q "1"; then
        echo "✅ External Secrets operator is ready"
    else
        echo "❌ External Secrets operator is not ready"
        exit 1
    fi
else
    echo "❌ External Secrets operator is not deployed"
    exit 1
fi

# Check node resources
echo "💾 Checking node resources..."
if kubectl top nodes &>/dev/null; then
    echo "📊 Node resource usage:"
    kubectl top nodes
else
    echo "⚠️  Metrics server not available, cannot check resource usage"
fi

# Check storage classes
echo "💿 Checking storage classes..."
if kubectl get storageclass &>/dev/null; then
    echo "✅ Storage classes available:"
    kubectl get storageclass
else
    echo "❌ No storage classes found"
    exit 1
fi

# Check if PostgreSQL cluster exists
echo "🗄️  Checking PostgreSQL cluster..."
if kubectl get cluster.postgresql.cnpg.io -n "${NAMESPACE}" &>/dev/null; then
    echo "✅ PostgreSQL clusters found:"
    kubectl get cluster.postgresql.cnpg.io -n "${NAMESPACE}"
else
    echo "⚠️  No PostgreSQL clusters found in namespace ${NAMESPACE}"
    echo "ℹ️  PostgreSQL cluster will need to be created during deployment"
fi

# Check if DeepAgents Runtime is available (only in production or if namespace exists)
if [ "$IS_PREVIEW_MODE" = false ] || kubectl get namespace intelligence-deepagents &>/dev/null; then
    echo "🤖 Checking DeepAgents Runtime availability..."
    if kubectl get deployment deepagents-runtime -n intelligence-deepagents &>/dev/null; then
        echo "✅ DeepAgents Runtime deployment found"
        
        # Check if it's ready
        ready_replicas=$(kubectl get deployment deepagents-runtime -n intelligence-deepagents -o jsonpath='{.status.readyReplicas}' || echo "0")
        desired_replicas=$(kubectl get deployment deepagents-runtime -n intelligence-deepagents -o jsonpath='{.spec.replicas}' || echo "1")
        
        if [[ "${ready_replicas}" == "${desired_replicas}" ]]; then
            echo "✅ DeepAgents Runtime is ready (${ready_replicas}/${desired_replicas})"
        else
            echo "⚠️  DeepAgents Runtime is not fully ready (${ready_replicas}/${desired_replicas})"
        fi
    else
        echo "⚠️  DeepAgents Runtime deployment not found"
        echo "ℹ️  DeepAgents Runtime may need to be deployed first"
    fi
else
    echo "ℹ️  Skipping DeepAgents Runtime check (preview mode, namespace not created yet)"
fi

echo "✅ Pre-deployment diagnostics completed successfully!"
echo "🚀 Infrastructure is ready for deployment"