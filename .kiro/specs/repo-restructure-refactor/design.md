# Design Document

## Overview

This design document outlines the technical approach for restructuring the `platform/04-apis/` directory to follow Crossplane best practices from platform-ref-multi-k8s. The restructuring will create a well-organized structure for platform APIs with proper CI/validation workflows.

## Architecture

### Current State

```
platform/04-apis/
├── crossplane.yaml          # ArgoCD Application
├── provider-config.yaml     # Provider configuration
└── compositions/
    └── webservice.yaml      # Combined XRD + Composition
```

### Target State

```
platform/04-apis/
├── .gitmodules             # upbound/build submodule reference
├── build/                  # upbound/build submodule (makelib includes)
├── crossplane.yaml         # Crossplane Configuration Package metadata
├── .xpkgignore            # Package exclusion patterns
├── Makefile               # Build system (includes from build/makelib/)
├── README.md              # API documentation
├── definitions/           # XRDs (API schemas)
│   ├── xwebservices.yaml
│   ├── xpostgresqls.yaml
│   └── xdragonflies.yaml
├── compositions/          # Implementations
│   ├── webservice-basic.yaml
│   ├── postgresql-basic.yaml
│   └── dragonfly-basic.yaml
├── examples/              # Example claims
│   ├── webservice-example.yaml
│   ├── postgresql-example.yaml
│   └── dragonfly-example.yaml
├── providers/             # Provider configs
│   └── provider-kubernetes.yaml
├── test/                  # E2E test setup
│   └── setup.sh
└── functions/             # Function references (optional)
    └── functions.yaml
```

### CI/CD Integration

```
.github/workflows/
├── platform-apis-ci.yaml   # Validate, build, and E2E test on PR
├── platform-apis-cd.yaml   # Publish packages on merge to main
└── platform-apis-e2e.yaml  # Full E2E tests (optional separate workflow)
```

## Components and Interfaces

### 1. Build System (upbound/build)

**Purpose:** Provide standardized makelib includes for building, testing, and publishing Crossplane packages

**Structure:**
```makefile
# platform/04-apis/Makefile
PROJECT_NAME := platform-apis
PROJECT_REPO := github.com/bizmatters/infra-platform

PLATFORMS ?= linux_amd64
-include build/makelib/common.mk

# Kubernetes tools (crossplane CLI, up CLI, kubectl)
UP_VERSION = v0.25.0
UPTEST_VERSION = v0.11.1
-include build/makelib/k8s_tools.mk

# Crossplane package building
XPKG_DIR = $(shell pwd)
XPKG_IGNORE = .github/workflows/*.yaml,examples/*.yaml,test/*.sh
XPKG_REG_ORGS ?= ghcr.io/bizmatters
XPKGS = $(PROJECT_NAME)
-include build/makelib/xpkg.mk

# Local testing with Crossplane
CROSSPLANE_NAMESPACE = crossplane-system
CROSSPLANE_ARGS = "--enable-usages"
-include build/makelib/local.xpkg.mk
-include build/makelib/controlplane.mk

# Submodule setup
fallthrough: submodules
	@echo Initial setup complete. Running make again...
	@make

submodules:
	@git submodule sync
	@git submodule update --init --recursive

# E2E testing
uptest: $(UPTEST) $(KUBECTL)
	@$(INFO) running E2E tests
	@KUBECTL=$(KUBECTL) CROSSPLANE_NAMESPACE=$(CROSSPLANE_NAMESPACE) \
		$(UPTEST) e2e examples/*.yaml --setup-script=test/setup.sh --default-timeout=600

# Custom targets
render:
	crossplane beta render examples/webservice-example.yaml \
		definitions/xwebservices.yaml compositions/webservice-basic.yaml -r

yamllint:
	@yamllint ./definitions ./compositions ./examples
```

**Key Design Decisions:**
- Use upbound/build as git submodule (not vendored)
- Makelib provides: `build.all`, `publish`, `controlplane.up`, tool installation
- Auto-installs crossplane CLI, up CLI, kubectl to `.work/tools/`
- Supports local testing with `make controlplane.up` (spins up kind cluster with Crossplane)
- E2E tests use `uptest` framework

### 2. XRD Definitions

**Purpose:** Define the API schemas for platform resources

**Structure:**
```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xwebservices.platform.bizmatters.io
spec:
  group: platform.bizmatters.io
  names:
    kind: XWebService
    plural: xwebservices
  claimNames:
    kind: WebService
    plural: webservices
  versions:
    - name: v1alpha1
      served: true
      referenceable: true
      schema:
        openAPIV3Schema:
          # Detailed schema with validation
```

**Key Design Decisions:**
- One XRD per file for clarity
- Group: `platform.bizmatters.io` for all platform APIs
- Version: Start with `v1alpha1`, evolve to `v1beta1`, then `v1`
- Claims enabled for namespace-scoped usage

### 3. Compositions with Pipeline Mode

**Purpose:** Implement XRDs using composition pipelines with conditional logic

**Structure:**
```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: webservice-basic
  labels:
    type: basic
spec:
  compositeTypeRef:
    apiVersion: platform.bizmatters.io/v1alpha1
    kind: XWebService
  mode: Pipeline
  pipeline:
    - step: patch-and-transform
      functionRef:
        name: function-conditional-patch-and-transform
      input:
        apiVersion: pt.fn.crossplane.io/v1beta1
        kind: Resources
        resources:
          - name: deployment
            base:
              apiVersion: kubernetes.crossplane.io/v1alpha2
              kind: Object
              spec:
                forProvider:
                  manifest:
                    apiVersion: apps/v1
                    kind: Deployment
            patches:
              # Field path patches
          
          - name: keda-scaledobject
            condition: observed.composite.resource.spec.scaling.enabled == true
            base:
              # KEDA ScaledObject
          
          - name: httproute
            condition: observed.composite.resource.spec.public == true
            base:
              apiVersion: kubernetes.crossplane.io/v1alpha2
              kind: Object
              spec:
                forProvider:
                  manifest:
                    apiVersion: gateway.networking.k8s.io/v1
                    kind: HTTPRoute
                    spec:
                      parentRefs:
                        - name: cilium-gateway  # Fixed platform constant
                          namespace: default
                      hostnames:
                        - example.com  # Patched from spec.hostname
                      rules:
                        - backendRefs:
                            - name: service-name  # Patched from composition
          
          - name: usage-gitops
            base:
              apiVersion: apiextensions.crossplane.io/v1alpha1
              kind: Usage
              spec:
                of:
                  apiVersion: platform.bizmatters.io/v1alpha1
                  kind: XWebService
                  resourceSelector:
                    matchControllerRef: true
                by:
                  apiVersion: gitops.platform.bizmatters.io/v1alpha1
                  kind: XGitOps
                  resourceSelector:
                    matchControllerRef: true
```

**Key Design Decisions:**
- Pipeline mode for conditional logic
- `function-conditional-patch-and-transform` for parameter-based resources
- Composition selectors using labels (`type: basic`, `type: advanced`)
- One composition per file
- Usage resources for deletion ordering (prevent parent deletion while children exist)

### 4. Provider Configuration

**Purpose:** Configure provider-kubernetes for in-cluster resource management

**Structure:**
```yaml
---
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-kubernetes
spec:
  package: xpkg.upbound.io/crossplane-contrib/provider-kubernetes:v0.14.0
---
apiVersion: kubernetes.crossplane.io/v1alpha1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: InjectedIdentity
```

**Key Design Decisions:**
- Use `InjectedIdentity` for in-cluster access (ServiceAccount)
- Dedicated RBAC for provider ServiceAccount
- ArgoCD sync wave "1" to ensure provider readiness

### 5. Crossplane Configuration Metadata

**Purpose:** Define configuration metadata for versioning and dependency management (logical grouping, not necessarily OCI artifact)

**Structure (crossplane.yaml):**
```yaml
apiVersion: meta.pkg.crossplane.io/v1alpha1
kind: Configuration
metadata:
  name: platform-apis
  annotations:
    meta.crossplane.io/maintainer: Platform Team
    meta.crossplane.io/source: github.com/bizmatters/infra-platform
    meta.crossplane.io/license: MIT
    meta.crossplane.io/description: |
      Platform APIs for self-service resource provisioning
spec:
  crossplane:
    version: ">=v1.14.1-0"
  dependsOn:
    - provider: xpkg.upbound.io/crossplane-contrib/provider-kubernetes
      version: "v0.14.0"
    - function: xpkg.upbound.io/crossplane-contrib/function-conditional-patch-and-transform
      version: "v0.4.0"
```

**Key Design Decisions:**
- Semantic versioning
- Renovate comments for automated updates
- `.xpkgignore` to exclude CI, examples, tests
- Configuration can be built as OCI image using `make build.all`

### 6. E2E Testing with Uptest

**Purpose:** Validate that composed resources reach Ready=True status

**Structure (test/setup.sh):**
```bash
#!/usr/bin/env bash
set -aeuo pipefail

echo "Setting up E2E test environment..."

# Wait for Crossplane to be ready
kubectl wait --for=condition=Available deployment/crossplane \
  -n crossplane-system --timeout=5m

# Wait for providers to be healthy
kubectl wait provider.pkg --all --for condition=Healthy --timeout=5m

# Wait for XRDs to be established
kubectl wait xrd --all --for condition=Established --timeout=5m

# Configure provider-kubernetes (uses in-cluster credentials)
cat <<EOF | kubectl apply -f -
apiVersion: kubernetes.crossplane.io/v1alpha1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: InjectedIdentity
EOF

echo "E2E test environment ready"
```

**Uptest Configuration:**
```yaml
# examples/webservice-example.yaml (with uptest annotations)
apiVersion: platform.bizmatters.io/v1alpha1
kind: WebService
metadata:
  name: test-webservice
  annotations:
    uptest.upbound.io/timeout: "600"
spec:
  image: nginx:latest
  port: 80
  public: true
  hostname: test.example.com
```

**Key Design Decisions:**
- Use `uptest` v0.11.1+ for E2E testing
- Tests validate resources reach `Ready=True` within timeout
- Setup script configures providers before tests run
- Tests run in ephemeral kind cluster (via `make controlplane.up`)
- Cleanup happens automatically after tests complete
- Critical for production confidence - validates full resource lifecycle

## Data Models

### WebService XRD Schema

```yaml
spec:
  type: object
  required:
    - image
    - port
  properties:
    image:
      type: string
      description: Container image to deploy
    port:
      type: integer
      description: Container port
      default: 8080
    replicas:
      type: integer
      description: Number of replicas
      default: 2
      minimum: 1
      maximum: 10
    scaling:
      type: object
      description: KEDA autoscaling configuration
      properties:
        enabled:
          type: boolean
          default: false
        minReplicas:
          type: integer
          default: 1
        maxReplicas:
          type: integer
          default: 10
        triggers:
          type: array
          items:
            type: object
    public:
      type: boolean
      description: Expose via HTTPRoute
      default: false
    hostname:
      type: string
      description: Hostname for HTTPRoute (REQUIRED if public=true)
      pattern: '^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$'
    observability:
      type: object
      properties:
        otelEnabled:
          type: boolean
          default: true
```

**Gateway Reference Design Decision:**
- **Gateway Name:** `cilium-gateway` (hardcoded in composition - platform constant)
- **Gateway Namespace:** `default` (hardcoded in composition - where Gateway exists)
- **Gateway API Version:** `gateway.networking.k8s.io/v1` (standard Gateway API, handled by Cilium)
- **Rationale:** Single shared Gateway for all workloads simplifies management. Gateway name is not exposed as XRD parameter.
- **Hostname:** User-provided via `spec.hostname` parameter (required when `public=true`, validated with DNS pattern)
- **HTTPRoute Namespace:** Same as claim namespace (patched from `spec.claimRef.namespace`)
- **Cilium Integration:** Cilium Gateway Controller watches HTTPRoute resources and configures Envoy proxy for L7 routing

### PostgreSQL XRD Schema

**Operator Integration:** CloudNativePG (cnpg.io/v1)

```yaml
spec:
  type: object
  required:
    - storageSize
  properties:
    version:
      type: string
      description: PostgreSQL version (maps to CloudNativePG Cluster.spec.imageName)
      enum: ["14", "15", "16"]
      default: "16"
    storageSize:
      type: string
      description: Storage size for PVC (maps to Cluster.spec.storage.size)
      pattern: '^[0-9]+Gi$'
    instances:
      type: integer
      description: Number of PostgreSQL instances (maps to Cluster.spec.instances)
      default: 1
      minimum: 1
      maximum: 3
    backupEnabled:
      type: boolean
      description: Enable S3/Azure backup (maps to Cluster.spec.backup)
      default: true
    monitoring:
      type: boolean
      description: Enable Prometheus monitoring (maps to Cluster.spec.monitoring)
      default: true
```

**Composition Implementation:**
- Creates CloudNativePG `Cluster` resource (apiVersion: postgresql.cnpg.io/v1)
- Maps `version` to `spec.imageName: ghcr.io/cloudnative-pg/postgresql:16`
- Maps `storageSize` to `spec.storage.size`
- Maps `instances` to `spec.instances` for HA configuration
- Conditionally creates `ScheduledBackup` resource when `backupEnabled=true`
- Adds `PodMonitor` resource when `monitoring=true`

### Dragonfly XRD Schema

**Operator Integration:** Dragonfly Operator (dragonflydb.io/v1alpha1)

```yaml
spec:
  type: object
  properties:
    memoryLimit:
      type: string
      description: Memory limit (maps to Dragonfly.spec.resources.limits.memory)
      default: "1Gi"
      pattern: '^[0-9]+[MGT]i$'
    persistence:
      type: boolean
      description: Enable persistence with PVC (maps to Dragonfly.spec.snapshot)
      default: false
    replication:
      type: object
      description: Replication configuration (maps to Dragonfly.spec.replicas)
      properties:
        enabled:
          type: boolean
          default: false
        replicas:
          type: integer
          description: Number of replica instances
          default: 2
          minimum: 1
          maximum: 5
```

**Composition Implementation:**
- Creates Dragonfly `Dragonfly` resource (apiVersion: dragonflydb.io/v1alpha1)
- Maps `memoryLimit` to `spec.resources.limits.memory` and `spec.args: ["--maxmemory=1gb"]`
- Conditionally creates PVC and configures `spec.snapshot.persistentVolumeClaimSpec` when `persistence=true`
- Maps `replication.replicas` to `spec.replicas` when `replication.enabled=true`
- Creates Service for Redis protocol compatibility (port 6379)

## Error Handling

### Composition Errors

**Strategy:** Use Crossplane's built-in error handling and status conditions

**Implementation:**
- Compositions report errors via `status.conditions`
- ArgoCD shows sync status and health
- Robusta alerts on failed compositions

### Validation Errors

**Strategy:** Catch errors early with OpenAPI validation and CI

**Implementation:**
- XRD schemas validate claims at admission time
- CI runs `crossplane beta render` to catch composition errors
- `yamllint` catches YAML syntax errors

### Provider Errors

**Strategy:** Monitor provider health and credentials

**Implementation:**
- Provider pods must be healthy before compositions apply
- ProviderConfig errors surface in provider status
- RBAC errors logged in provider pod logs

## Testing Strategy

### Local Testing

**Tools:**
- `make render` - Validate compositions generate correct resources
- `make yamllint` - Validate YAML syntax
- `crossplane beta validate` - Validate XRD schemas

**Workflow:**
1. Developer creates/modifies XRD or Composition
2. Runs `make render` to test with examples
3. Runs `make yamllint` to check syntax
4. Commits changes

### CI Testing

**Pipeline:**
1. **Lint:** Run `yamllint` on all YAML files
2. **Render:** Run `crossplane beta render` on all examples
3. **Build:** Build OCI package with `make build.all`
4. **E2E:** Run `make uptest` to validate resource lifecycle
5. **Publish:** Push package to registry on merge to main

**GitHub Actions:**
```yaml
name: Platform APIs CI
on: [pull_request]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: true  # Required for upbound/build
      
      - name: Setup Build System
        run: make submodules
      
      - name: Lint YAML
        run: make yamllint
      
      - name: Render Compositions
        run: make render
      
      - name: Build Package
        run: make build.all
      
      - name: Run E2E Tests
        run: make uptest
        env:
          UPTEST_CLOUD_CREDENTIALS: ${{ secrets.UPTEST_CLOUD_CREDENTIALS }}
```

### Integration Testing (Optional)

**Approach:** Use `uptest` framework for end-to-end testing

**Scope:**
- Deploy example claims to test cluster
- Verify resources are created correctly
- Verify KEDA scaling works
- Verify HTTPRoute routing works

**Note:** Integration testing is optional for initial implementation

## Implementation Phases

### Phase 1: Build System Setup
- Add upbound/build as git submodule
- Create Makefile with makelib includes
- Configure tool versions (UP_VERSION, UPTEST_VERSION)
- Test `make submodules` and `make build.init`

### Phase 2: Directory Restructuring
- Create new directory structure (definitions/, compositions/, examples/, providers/, test/)
- Move existing webservice.yaml to new structure
- Split XRD and Composition into separate files
- Update ArgoCD Application to point to new structure

### Phase 3: Composition Pipeline Migration
- Convert webservice composition to pipeline mode
- Add conditional KEDA ScaledObject
- Add conditional HTTPRoute
- Test with examples

### Phase 4: Additional APIs
- Create PostgreSQL XRD and Composition
- Create Dragonfly XRD and Composition
- Create examples for each

### Phase 5: E2E Testing Setup
- Create test/setup.sh for provider configuration
- Add uptest annotations to examples
- Configure `make uptest` target
- Test locally with `make controlplane.up`

### Phase 6: CI/CD Setup
- Create GitHub Actions workflows with submodule checkout
- Add `make build.all` to CI
- Add `make uptest` to CI
- Create `.xpkgignore`
- Create `crossplane.yaml` configuration metadata
- Create `.github/renovate.json5` with custom regex managers

### Phase 7: Provider Configuration
- Create provider-kubernetes configuration
- Create RBAC for provider ServiceAccount
- Update ArgoCD sync waves

### Phase 8: Documentation
- Create platform/04-apis/README.md
- Create docs/references.md
- Add Mermaid diagrams to docs/architecture/
- Document usage examples

## Security Considerations

### RBAC for Provider

**Principle:** Least privilege

**Implementation:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: provider-kubernetes-role
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["gateway.networking.k8s.io"]
    resources: ["httproutes"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["keda.sh"]
    resources: ["scaledobjects"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```

### Secret Management

**Approach:** Use External Secrets Operator

**Implementation:**
- PostgreSQL credentials synced from GitHub Secrets
- Connection secrets written to namespace by Crossplane
- No secrets in Git

### Network Policies

**Approach:** Cilium NetworkPolicies

**Implementation:**
- Compositions can optionally create NetworkPolicies
- Default deny, explicit allow
- Integrated with Gateway API

## Performance Considerations

### Composition Rendering

**Challenge:** Complex compositions may be slow to render

**Mitigation:**
- Keep compositions focused and simple
- Use composition functions efficiently
- Monitor Crossplane controller performance

### Provider Scalability

**Challenge:** Single provider managing many resources

**Mitigation:**
- Monitor provider pod resource usage
- Scale provider deployment if needed
- Consider multiple ProviderConfigs for isolation

## Monitoring and Observability

### Metrics

**What to Monitor:**
- Composition sync status (via ArgoCD)
- Provider health (pod status)
- Claim creation/deletion rate
- Composition rendering time

**Tools:**
- Prometheus for metrics
- Grafana for dashboards
- Robusta for alerts

### Logging

**What to Log:**
- Composition errors
- Provider errors
- Validation failures

**Tools:**
- Promtail collects logs
- Loki stores logs
- Grafana for querying

### Alerting

**Alerts:**
- Composition sync failures
- Provider pod crashes
- Validation errors in CI

**Integration:**
- Robusta sends alerts to Kagent
- Kagent proposes fixes via PR

## Dependencies

### External Dependencies

- Crossplane >= v1.14.1
- provider-kubernetes v0.14.0
- function-conditional-patch-and-transform v0.4.0
- ArgoCD (existing)
- Cilium (existing)
- KEDA (existing)

### Internal Dependencies

- Gateway API Gateway (existing in platform/01-foundation/)
- External Secrets Operator (existing)
- Prometheus/Loki (existing in platform/02-observability/)

## Open Questions

1. **Versioning Strategy:** How to handle breaking changes in XRDs? (Use composition selectors, or create new XRD versions?)
2. **Testing Scope:** Should we implement full integration testing with `uptest`, or rely on CI rendering + manual testing?
3. **Provider Isolation:** Should we use multiple ProviderConfigs for tenant isolation, or single shared provider?
4. **Renovate Regex:** What specific version patterns in Makefile need automated updates? (Crossplane CLI version, provider versions, etc.)

## Success Criteria

The restructuring is successful when:

1. ✅ Build system uses upbound/build submodule with makelib includes
2. ✅ Directory structure follows platform-ref-multi-k8s pattern
3. ✅ All compositions use pipeline mode with functions and Usage resources
4. ✅ E2E tests with uptest validate resources reach Ready=True
5. ✅ CI builds OCI packages and runs full test suite
6. ✅ Configuration metadata is complete and valid
7. ✅ WebService, PostgreSQL, and Dragonfly APIs are functional
8. ✅ Examples work end-to-end in local and CI environments
9. ✅ Documentation is complete and clear
10. ✅ Renovate automates dependency updates including Makefile versions
11. ✅ Packages can be published to registry with `make publish`
