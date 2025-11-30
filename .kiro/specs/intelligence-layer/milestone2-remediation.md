# Milestone 2 Remediation Plan

**Goal:** Deploy and validate Intelligence Layer (Qdrant + docs-mcp + Librarian Agent)

**Current State Analysis (Post-Cluster Restart):**
- ✅ Worker node memory increased from 2GB → 4GB (OOM issue resolved)
- ✅ Kagent operator installed via direct Helm (v0.7.4) with all 10 agents
- ✅ KEDA installed (foundation layer)
- ✅ ArgoCD installed and operational
- ❌ Qdrant NOT deployed (intelligence namespace empty)
- ❌ docs-mcp NOT deployed (Docker image doesn't exist)
- ❌ Librarian Agent NOT deployed
- ⚠️ Observability stack consuming resources (can be disabled for testing)

---

## Prerequisites

### P1. Verify Cluster Health
```bash
# Check nodes are Ready
kubectl get nodes
# Expected: Both nodes Ready with 4GB worker memory

# Check ArgoCD is running
kubectl get pods -n argocd
# Expected: All ArgoCD pods Running (repo-server, application-controller, server)

# Check Kagent operator is running
kubectl get pods -n kagent | grep controller
# Expected: kagent-controller-* Running

# Check KEDA is running
kubectl get pods -n kube-system | grep keda
# Expected: keda-operator and keda-metrics-apiserver Running
```

### P2. Verify Crossplane Provider
```bash
# Check provider-kubernetes is healthy
kubectl get providers
# Expected: provider-kubernetes HEALTHY=True INSTALLED=True

# Verify ProviderConfig exists
kubectl get providerconfigs
# Expected: default ProviderConfig present
```

### P3. (Optional) Disable Observability Stack
**Only if cluster is still resource-constrained:**
```bash
# Scale down observability to free memory
kubectl delete application observability -n argocd

# This removes: Prometheus, Loki, Tempo, Grafana, Robusta
# Saves ~1-1.5GB memory
```

---

## Phase 1: Deploy Qdrant Vector Database

### 1.1 Create Qdrant Instance Claim
**File:** `platform/03-intelligence/qdrant.yaml`
```yaml
apiVersion: intelligence.bizmatters.io/v1alpha1
kind: XQdrant
metadata:
  name: platform-qdrant
  namespace: argocd
spec:
  parameters:
    namespace: intelligence
    replicas: 1
    storageSize: 10Gi
```

**Action:**
```bash
# Apply the Qdrant claim
kubectl apply -f platform/03-intelligence/qdrant.yaml

# Watch creation
kubectl get xqdrant -n argocd -w
kubectl get pods -n intelligence -w
```

**Success Criteria:**
- XQdrant resource shows READY=True SYNCED=True
- `qdrant-0` pod Running in `intelligence` namespace
- PVC bound with `local-path` storage class
- Service `qdrant.intelligence.svc.cluster.local` exists

**Troubleshooting:**
```bash
# If PVC pending
kubectl describe pvc -n intelligence
# Ensure storageClassName: local-path exists in composition

# If pod crashes
kubectl logs -n intelligence qdrant-0
kubectl describe pod -n intelligence qdrant-0
```

### 1.2 Verify Qdrant Connectivity
```bash
# Port-forward to test
kubectl port-forward -n intelligence svc/qdrant 6333:6333

# In another terminal, test HTTP API
curl http://localhost:6333/collections
# Expected: {"result": [], "status": "ok", "time": ...}
```

---

## Phase 2: Build and Deploy docs-mcp MCP Server

### 2.1 Build docs-mcp Docker Image
**Issue:** Image `ghcr.io/arun4infra/docs-mcp:latest` doesn't exist in registry

**Solution:** Trigger GitHub Actions workflow manually

```bash
# Check if workflow file exists
ls -la .github/workflows/build-docs-mcp.yaml

# Trigger via GitHub UI or gh CLI
gh workflow run build-docs-mcp.yaml --ref main

# Monitor workflow
gh run list --workflow=build-docs-mcp.yaml
gh run watch $(gh run list --workflow=build-docs-mcp.yaml --limit 1 --json databaseId --jq '.[0].databaseId')
```

**Alternative:** Build and push locally
```bash
cd services/docs-mcp/
docker build -t ghcr.io/arun4infra/docs-mcp:v0.1.0 .
docker push ghcr.io/arun4infra/docs-mcp:v0.1.0

# Update composition to use specific tag
# Edit platform/03-intelligence/compositions/docs-mcp.yaml line 142
# Change: image: ghcr.io/arun4infra/docs-mcp:latest
# To:     image: ghcr.io/arun4infra/docs-mcp:v0.1.0
```

### 2.2 Create GitHub Bot Token Secret
**docs-mcp requires GitHub token for PR operations**

```bash
# Create placeholder secret (External Secrets Operator will replace in production)
kubectl create namespace intelligence --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic github-bot-token \
  -n intelligence \
  --from-literal=token="PLACEHOLDER_GITHUB_TOKEN"

# For production: Configure External Secrets Operator
# See: platform/03-intelligence/docs/github-bot-setup.md
```

### 2.3 Deploy docs-mcp via Crossplane
**File:** `platform/03-intelligence/docs-mcp-claim.yaml`
```yaml
apiVersion: intelligence.bizmatters.io/v1alpha1
kind: XDocsMCP
metadata:
  name: platform-docs-mcp
  namespace: argocd
spec:
  parameters:
    namespace: intelligence
    image: ghcr.io/arun4infra/docs-mcp:v0.1.0
    githubTokenSecretRef:
      name: github-bot-token
      key: token
    replicas:
      min: 0  # KEDA scale-to-zero
      max: 5
```

**Action:**
```bash
# Apply claim
kubectl apply -f platform/03-intelligence/docs-mcp-claim.yaml

# Watch deployment
kubectl get xdocsmcp -n argocd -w
kubectl get pods -n intelligence -l app=docs-mcp -w
```

**Success Criteria:**
- XDocsMCP resource shows READY=True SYNCED=True
- `docs-mcp-*` pod Running in `intelligence` namespace
- Service `docs-mcp.intelligence.svc.cluster.local` exists
- KEDA ScaledObject created and monitoring
- Pod can connect to Qdrant (check logs)

**Troubleshooting:**
```bash
# Check deployment
kubectl describe deployment -n intelligence docs-mcp

# Check pod logs
kubectl logs -n intelligence -l app=docs-mcp --tail=50

# Common issues:
# - ImagePullBackOff: Image not built/pushed
# - CrashLoopBackOff: Check QDRANT_URL env var, GitHub token
# - Pending: Resource limits too high for 4GB worker
```

---

## Phase 3: Deploy Librarian Agent

### 3.1 Fix Librarian Agent CRD
**Issue:** Current `librarian-agent.yaml` is malformed - not a proper Kagent Agent CRD

**Required Format (from context7):**
```yaml
apiVersion: kagent.dev/v1alpha2  # NOT kagent.bizmatters.io
kind: Agent
metadata:
  name: librarian-agent
  namespace: intelligence
spec:
  systemPrompt: |
    [Your system prompt here - already well-defined in existing file]

  # Reference the ModelConfig (created by Kagent Helm chart)
  modelConfigRef:
    name: default-model-config
    namespace: kagent

  # Reference the docs-mcp tools via ToolServer or RemoteMCPServer
  toolServers:
    - name: docs-mcp-tools
      namespace: intelligence
```

### 3.2 Create docs-mcp ToolServer/RemoteMCPServer
**Kagent needs to discover docs-mcp tools via MCP protocol**

**Option A: Using kmcp (Kagent's MCP controller)**
```yaml
apiVersion: kagent.dev/v1alpha2
kind: RemoteMCPServer
metadata:
  name: docs-mcp-tools
  namespace: intelligence
spec:
  url: http://docs-mcp.intelligence.svc.cluster.local:80
  transport: sse  # Server-Sent Events (MCP standard)
```

**Option B: Using legacy ToolServer (if kmcp not available)**
```yaml
apiVersion: kagent.dev/v1alpha1
kind: ToolServer
metadata:
  name: docs-mcp-tools
  namespace: intelligence
spec:
  config:
    streamableHttp:
      url: http://docs-mcp.intelligence.svc.cluster.local:80
      timeout: 30s
  description: "Documentation automation tools (validate, create, search, commit)"
```

### 3.3 Update ModelConfig for Librarian
**Current default-model-config uses placeholder API key**

```bash
# Update the kagent-openai secret with real OpenAI key
kubectl delete secret kagent-openai -n kagent
kubectl create secret generic kagent-openai \
  -n kagent \
  --from-literal=OPENAI_API_KEY="YOUR_ACTUAL_OPENAI_KEY"

# Restart Kagent controller to pick up new key
kubectl rollout restart deployment kagent-controller -n kagent
```

### 3.4 Deploy Librarian Agent
```bash
# Fix and apply the agent CRD
kubectl apply -f platform/03-intelligence/compositions/librarian-agent.yaml

# Verify deployment
kubectl get agents -n intelligence
kubectl describe agent librarian-agent -n intelligence

# Check if agent pod is created (if using agent-per-pod mode)
kubectl get pods -n intelligence -l agent=librarian-agent
```

**Success Criteria:**
- Agent CRD created: `kubectl get agents -n intelligence`
- Agent shows READY=True ACCEPTED=True
- Agent appears in Kagent UI (if deployed)
- Agent can invoke docs-mcp tools (test via kubectl exec or UI)

---

## Phase 4: Integration Testing

### 4.1 Test Qdrant → docs-mcp Connection
```bash
# Exec into docs-mcp pod
kubectl exec -it -n intelligence deployment/docs-mcp -- sh

# Test Qdrant connection (inside pod)
curl http://qdrant.intelligence.svc.cluster.local:6333/collections
# Expected: JSON response with collections list
```

### 4.2 Test docs-mcp Tools
```bash
# Port-forward docs-mcp
kubectl port-forward -n intelligence svc/docs-mcp 8080:80

# Test MCP tools endpoint (if HTTP API exposed)
curl http://localhost:8080/tools
# Expected: List of available tools (validate_doc, create_doc, etc.)
```

### 4.3 Test Librarian Agent Invocation
**Via Kagent UI (if deployed):**
1. Access Kagent UI: `kubectl port-forward -n kagent svc/kagent-ui 3000:80`
2. Open http://localhost:3000
3. Find "librarian-agent" in agent list
4. Send test query: "Validate the file artifacts/specs/webservice.md"
5. Verify agent calls `validate_doc` tool

**Via kubectl (if agent creates pods):**
```bash
# Check agent logs
kubectl logs -n intelligence -l agent=librarian-agent --tail=100

# Look for MCP tool invocations in logs
```

### 4.4 Verify KEDA Scale-to-Zero
```bash
# Wait 5 minutes with no traffic
sleep 300

# Check docs-mcp replicas
kubectl get deployment -n intelligence docs-mcp
# Expected: READY 0/0 (scaled to zero)

# Trigger scale-up (send request)
kubectl port-forward -n intelligence svc/docs-mcp 8080:80 &
curl http://localhost:8080/health

# Check replicas again
kubectl get deployment -n intelligence docs-mcp -w
# Expected: Scales from 0 → 1 within 30 seconds
```

---

## Phase 5: Milestone 2 Validation

### 5.1 Component Health Check
```bash
# Run comprehensive health check
cat <<'EOF' | bash
#!/bin/bash
echo "=== Milestone 2 Health Check ==="
echo ""
echo "1. Qdrant:"
kubectl get xqdrant -n argocd
kubectl get pods -n intelligence -l app=qdrant
kubectl get svc -n intelligence qdrant
echo ""
echo "2. docs-mcp:"
kubectl get xdocsmcp -n argocd
kubectl get deployment -n intelligence docs-mcp
kubectl get scaledobject -n intelligence docs-mcp-scaler
echo ""
echo "3. Librarian Agent:"
kubectl get agents -n intelligence librarian-agent
kubectl describe agent -n intelligence librarian-agent | grep -A 5 "Status:"
echo ""
echo "4. Integration:"
echo "   - Qdrant endpoint: http://qdrant.intelligence.svc.cluster.local:6333"
echo "   - docs-mcp endpoint: http://docs-mcp.intelligence.svc.cluster.local:80"
echo "   - Agent modelConfig: default-model-config"
echo ""
EOF
```

### 5.2 Success Criteria Checklist
- [ ] Qdrant StatefulSet Running (1/1 ready)
- [ ] Qdrant PVC Bound (10Gi with local-path storage)
- [ ] Qdrant HTTP API responding on port 6333
- [ ] docs-mcp Deployment created via Crossplane
- [ ] docs-mcp pod can connect to Qdrant (check logs)
- [ ] KEDA ScaledObject monitoring docs-mcp
- [ ] docs-mcp scales to 0 after 5 min idle
- [ ] Librarian Agent CRD created and READY
- [ ] Agent has valid ModelConfig reference
- [ ] Agent has docs-mcp tools registered
- [ ] Agent can invoke at least one MCP tool successfully

### 5.3 Known Limitations (Accept for Milestone 2)
1. **GitHub token is placeholder:** External Secrets Operator not configured (manual step required)
2. **No Prometheus metrics:** Observability stack disabled to save memory
3. **KEDA scale-up trigger disabled:** Prometheus not available (CPU trigger still works)
4. **Agent testing manual:** No automated agent invocation test (requires Kagent UI or API)
5. **Kagent installed outside GitOps:** Direct Helm install due to ArgoCD OCI 403 error

---

## Troubleshooting Guide

### Issue: Qdrant PVC Pending
**Symptom:** PVC stuck in Pending state
**Diagnosis:**
```bash
kubectl describe pvc -n intelligence qdrant-storage-qdrant-0
```
**Fix:** Ensure composition has `storageClassName: local-path` (already fixed in composition)

### Issue: docs-mcp ImagePullBackOff
**Symptom:** Pod can't pull image
**Diagnosis:**
```bash
kubectl describe pod -n intelligence <pod-name> | grep -A 5 "Events:"
```
**Fix:**
- Trigger GitHub Actions workflow to build image
- OR build and push locally (see Phase 2.1)
- Update claim to use specific tag instead of `:latest`

### Issue: docs-mcp CrashLoopBackOff
**Symptom:** Pod starts then crashes
**Diagnosis:**
```bash
kubectl logs -n intelligence <pod-name>
```
**Common causes:**
- Qdrant not reachable: Check QDRANT_URL env var
- GitHub token invalid: Check secret exists
- Port conflict: Ensure port 8080 not used

### Issue: Librarian Agent Not Ready
**Symptom:** Agent shows READY=False
**Diagnosis:**
```bash
kubectl describe agent -n intelligence librarian-agent
```
**Common causes:**
- Invalid ModelConfig reference (check namespace)
- ToolServer/RemoteMCPServer not found
- OpenAI API key still placeholder (see Phase 3.3)

### Issue: Agent Can't Invoke Tools
**Symptom:** Agent created but tools don't work
**Diagnosis:**
- Check docs-mcp service exists: `kubectl get svc -n intelligence docs-mcp`
- Check ToolServer/RemoteMCPServer created
- Check agent logs for connection errors

### Issue: KEDA Not Scaling
**Symptom:** docs-mcp stays at 1 replica
**Diagnosis:**
```bash
kubectl describe scaledobject -n intelligence docs-mcp-scaler
kubectl logs -n kube-system -l app=keda-operator
```
**Fix:**
- If Prometheus trigger failing: Accept this (observability disabled)
- CPU trigger should still work for scale-up

---

## Rollback Procedure

If deployment fails catastrophically:

```bash
# Delete all intelligence layer resources
kubectl delete xqdrant platform-qdrant -n argocd
kubectl delete xdocsmcp platform-docs-mcp -n argocd
kubectl delete agent librarian-agent -n intelligence
kubectl delete namespace intelligence

# Reset ArgoCD intelligence app
kubectl delete application intelligence -n argocd
kubectl apply -f platform/03-intelligence.yaml

# Uninstall Kagent (if needed)
helm uninstall kagent -n kagent
kubectl delete namespace kagent
```

---

## Post-Deployment Actions (Beyond Milestone 2)

1. **Enable Observability:** Re-enable Prometheus for KEDA metrics
2. **Configure External Secrets:** Set up GitHub bot token via External Secrets Operator
3. **GitOps Kagent:** Fix ArgoCD OCI 403 error and redeploy Kagent via ArgoCD
4. **CI Integration:** Test auto-fix workflow with actual PR
5. **Distillation Workflow:** Test runbook creation from docs/ notes
6. **Load Testing:** Simulate 10 concurrent requests to test KEDA scaling

---

## File Changes Required

### New Files to Create
1. `.kiro/specs/intelligence-layer/milestone2-remediation.md` (this file)
2. `platform/03-intelligence/qdrant.yaml` (Qdrant claim)
3. `platform/03-intelligence/docs-mcp-claim.yaml` (docs-mcp claim)

### Files to Fix
1. `platform/03-intelligence/compositions/librarian-agent.yaml`
   - Change apiVersion to `kagent.dev/v1alpha2`
   - Fix spec format per Kagent CRD schema
   - Add modelConfigRef and toolServers

### Files Already Correct (No Changes)
- `platform/03-intelligence/compositions/qdrant.yaml` ✅ (storageClassName fixed)
- `platform/03-intelligence/compositions/docs-mcp.yaml` ✅
- `platform/03-intelligence/definitions/xqdrant.yaml` ✅
- `platform/03-intelligence/definitions/xdocsmcp.yaml` ✅

---

## Execution Order Summary

1. **Verify Prerequisites** (P1-P3)
2. **Deploy Qdrant** (Phase 1)
3. **Build docs-mcp image** (Phase 2.1)
4. **Deploy docs-mcp** (Phase 2.2-2.3)
5. **Fix Librarian Agent** (Phase 3.1-3.2)
6. **Deploy Librarian Agent** (Phase 3.3-3.4)
7. **Run Integration Tests** (Phase 4)
8. **Validate Milestone** (Phase 5)

**Estimated Time:** 1-2 hours (including build times and wait for scale-to-zero test)
