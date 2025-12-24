#!/bin/bash
set -euo pipefail

# Service Health Verification After Deployment
# Validates that the deployed service is healthy and functioning

NAMESPACE="${NAMESPACE:-intelligence-orchestrator}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-ide-orchestrator}"
SERVICE_NAME="${SERVICE_NAME:-ide-orchestrator}"
HEALTH_ENDPOINT="${HEALTH_ENDPOINT:-/api/health}"

echo "🔍 Running post-deployment diagnostics..."

# Check deployment status
echo "📋 Checking deployment status..."
if ! kubectl get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" &>/dev/null; then
    echo "❌ Deployment ${DEPLOYMENT_NAME} not found"
    exit 1
fi

# Get deployment details
ready_replicas=$(kubectl get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}' || echo "0")
desired_replicas=$(kubectl get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}' || echo "1")
available_replicas=$(kubectl get deployment "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.availableReplicas}' || echo "0")

echo "📊 Deployment status:"
echo "  Ready: ${ready_replicas}/${desired_replicas}"
echo "  Available: ${available_replicas}/${desired_replicas}"

if [[ "${ready_replicas}" != "${desired_replicas}" ]]; then
    echo "❌ Deployment is not fully ready"
    exit 1
fi

echo "✅ Deployment is ready"

# Check pod status
echo "🔍 Checking pod status..."
kubectl get pods -n "${NAMESPACE}" -l app="${DEPLOYMENT_NAME}" -o wide

# Check for any failed pods
failed_pods=$(kubectl get pods -n "${NAMESPACE}" -l app="${DEPLOYMENT_NAME}" --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l || echo "0")
if [[ "${failed_pods}" -gt 0 ]]; then
    echo "❌ Found ${failed_pods} failed pods"
    kubectl get pods -n "${NAMESPACE}" -l app="${DEPLOYMENT_NAME}" --field-selector=status.phase!=Running
    exit 1
fi

echo "✅ All pods are running"

# Check service
echo "🌐 Checking service..."
if kubectl get service "${SERVICE_NAME}" -n "${NAMESPACE}" &>/dev/null; then
    echo "✅ Service ${SERVICE_NAME} exists"
    kubectl get service "${SERVICE_NAME}" -n "${NAMESPACE}" -o wide
else
    echo "❌ Service ${SERVICE_NAME} not found"
    exit 1
fi

# Test service connectivity
echo "🔗 Testing service connectivity..."
service_ip=$(kubectl get service "${SERVICE_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.clusterIP}')
service_port=$(kubectl get service "${SERVICE_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.ports[0].port}')

if [[ -n "${service_ip}" && -n "${service_port}" ]]; then
    echo "🔍 Testing connection to ${service_ip}:${service_port}..."
    
    # Use a test pod to check connectivity
    kubectl run connectivity-test \
        --image=curlimages/curl:latest \
        --rm -i --restart=Never \
        --timeout=30s \
        -- curl -s --connect-timeout 10 "http://${service_ip}:${service_port}${HEALTH_ENDPOINT}" || {
        echo "❌ Service connectivity test failed"
        exit 1
    }
    
    echo "✅ Service is responding"
else
    echo "❌ Could not determine service IP or port"
    exit 1
fi

# Check database connectivity
echo "🗄️  Checking database connectivity..."
if kubectl get secret ide-orchestrator-db-app -n "${NAMESPACE}" &>/dev/null; then
    echo "✅ Database secret exists"
    
    # Test database connection from the application pod
    pod_name=$(kubectl get pods -n "${NAMESPACE}" -l app="${DEPLOYMENT_NAME}" -o jsonpath='{.items[0].metadata.name}')
    if [[ -n "${pod_name}" ]]; then
        echo "🔍 Testing database connection from pod ${pod_name}..."
        
        kubectl exec "${pod_name}" -n "${NAMESPACE}" -- sh -c '
            if command -v psql &> /dev/null; then
                psql "${DATABASE_URL}" -c "SELECT 1;" &>/dev/null && echo "Database connection successful" || echo "Database connection failed"
            else
                echo "psql not available in container, skipping database test"
            fi
        ' || echo "⚠️  Could not test database connection"
    fi
else
    echo "⚠️  Database secret not found"
fi

# Check logs for errors
echo "📋 Checking recent logs for errors..."
kubectl logs -n "${NAMESPACE}" -l app="${DEPLOYMENT_NAME}" --tail=50 | grep -i error || echo "No errors found in recent logs"

# Resource usage
echo "💾 Checking resource usage..."
if kubectl top pods -n "${NAMESPACE}" -l app="${DEPLOYMENT_NAME}" &>/dev/null; then
    echo "📊 Pod resource usage:"
    kubectl top pods -n "${NAMESPACE}" -l app="${DEPLOYMENT_NAME}"
else
    echo "⚠️  Metrics not available"
fi

# Final health check
echo "🏥 Final health check..."
kubectl run health-check \
    --image=curlimages/curl:latest \
    --rm -i --restart=Never \
    --timeout=30s \
    -- curl -s -f "http://${service_ip}:${service_port}${HEALTH_ENDPOINT}" && {
    echo "✅ Health check passed"
} || {
    echo "❌ Health check failed"
    exit 1
}

echo "✅ Post-deployment diagnostics completed successfully!"
echo "🎉 Service is healthy and ready to serve traffic"