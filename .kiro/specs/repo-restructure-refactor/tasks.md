# Implementation Plan

- [ ] 1. Setup build system with upbound/build submodule
  - Add upbound/build as git submodule: `git submodule add https://github.com/upbound/build build`
  - Create initial Makefile with makelib includes
  - Configure tool versions (UP_VERSION=v0.25.0, UPTEST_VERSION=v0.11.1)
  - **Test:** Run `make submodules` - should sync and update submodules
  - **Expected Output:** `build/` directory exists with makelib files
  - **Test:** Run `make build.init` - should install tools to `.work/tools/`
  - **Expected Output:** crossplane CLI, up CLI, kubectl installed
  - _Requirements: 5.1, 5.2, 5.5_

- [ ] 2. Create directory structure for platform APIs
  - Create subdirectories: `definitions/`, `compositions/`, `examples/`, `providers/`, `test/`
  - **Test:** Run `ls -la platform/04-apis/`
  - **Expected Output:** All subdirectories exist
  - **Test:** Run `tree platform/04-apis/` (if available)
  - **Expected Output:** Clean directory structure matching design
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5_

- [ ] 3. Split existing webservice.yaml into XRD and Composition
  - [ ] 3.1 Extract XRD to definitions/xwebservices.yaml
    - Include OpenAPI v3 schema with validation (image, port, replicas, scaling, public, hostname)
    - Add connectionSecretKeys if needed
    - **Test:** Run `kubectl apply --dry-run=client -f definitions/xwebservices.yaml`
    - **Expected Output:** No errors, XRD validates successfully
    - **Test:** Check schema has required fields: `yq '.spec.versions[0].schema.openAPIV3Schema.properties' definitions/xwebservices.yaml`
    - **Expected Output:** Shows image, port, replicas, scaling, public, hostname properties
    - _Requirements: 3.1, 3.2, 3.5_
  
  - [ ] 3.2 Extract Composition to compositions/webservice-basic.yaml
    - Keep existing functionality intact (Deployment, Service)
    - **Test:** Run `kubectl apply --dry-run=client -f compositions/webservice-basic.yaml`
    - **Expected Output:** No errors, Composition validates
    - **Test:** Verify compositeTypeRef matches XRD: `yq '.spec.compositeTypeRef' compositions/webservice-basic.yaml`
    - **Expected Output:** `apiVersion: platform.bizmatters.io/v1alpha1, kind: XWebService`
    - _Requirements: 1.3_
  
  - [ ] 3.3 Create example claim in examples/webservice-example.yaml
    - Include test values for all parameters
    - **Test:** Run `kubectl apply --dry-run=client -f examples/webservice-example.yaml`
    - **Expected Output:** No validation errors
    - **Test:** Run `crossplane beta render examples/webservice-example.yaml definitions/xwebservices.yaml compositions/webservice-basic.yaml`
    - **Expected Output:** Renders Deployment and Service resources successfully
    - _Requirements: 1.4, 12.2_

- [ ] 4. Convert WebService composition to pipeline mode
  - [ ] 4.1 Update composition to use mode: Pipeline
    - Add pipeline section with function-conditional-patch-and-transform
    - **Test:** Verify mode is set: `yq '.spec.mode' compositions/webservice-basic.yaml`
    - **Expected Output:** `Pipeline`
    - **Test:** Verify function ref: `yq '.spec.pipeline[0].functionRef.name' compositions/webservice-basic.yaml`
    - **Expected Output:** `function-conditional-patch-and-transform`
    - _Requirements: 2.1, 2.2_
  
  - [ ] 4.2 Implement conditional KEDA ScaledObject
    - Add condition: `observed.composite.resource.spec.scaling.enabled == true`
    - **Test:** Render with scaling disabled: `crossplane beta render examples/webservice-example.yaml ...` (scaling.enabled=false)
    - **Expected Output:** No ScaledObject in output
    - **Test:** Render with scaling enabled: modify example to set scaling.enabled=true, render again
    - **Expected Output:** ScaledObject appears in output
    - _Requirements: 2.3_
  
  - [ ] 4.3 Implement conditional HTTPRoute for public exposure
    - Add condition: `observed.composite.resource.spec.public == true`
    - Use Gateway API v1: `apiVersion: gateway.networking.k8s.io/v1`
    - Hardcode Gateway reference: `name: cilium-gateway, namespace: default`
    - **Test:** Render with public=false
    - **Expected Output:** No HTTPRoute in output
    - **Test:** Render with public=true and hostname set
    - **Expected Output:** HTTPRoute with parentRefs pointing to cilium-gateway in default namespace
    - **Test:** Verify Gateway API version: `yq '.apiVersion' <rendered-httproute>`
    - **Expected Output:** `gateway.networking.k8s.io/v1`
    - **Test:** Verify Gateway reference: `yq '.spec.parentRefs[0]' <rendered-httproute>`
    - **Expected Output:** `name: cilium-gateway, namespace: default`
    - **Test:** Verify hostname is patched: `yq '.spec.hostnames[0]' <rendered-httproute>`
    - **Expected Output:** Matches `spec.hostname` from claim
    - _Requirements: 2.4, 10.1, 10.2_
  
  - [ ] 4.4 Add Usage resources for deletion ordering
    - Create Usage resources for child dependencies (if any)
    - **Test:** Render composition and check for Usage resources
    - **Expected Output:** Usage resources present if composition has child dependencies
    - _Requirements: 2.5_
  
  - [ ] 4.5 Validate complete pipeline composition
    - **Test:** Run `make render` (should render all examples)
    - **Expected Output:** All examples render successfully with correct conditional resources
    - **Test:** Run `make yamllint`
    - **Expected Output:** No YAML syntax errors
    - _Requirements: 8.1, 8.5_

- [ ] 5. Create PostgreSQL XRD and Composition
  - [ ] 5.1 Create definitions/xpostgresqls.yaml
    - Define schema: version (enum: 14,15,16), storageSize (pattern), instances, backupEnabled, monitoring
    - **Test:** Run `kubectl apply --dry-run=client -f definitions/xpostgresqls.yaml`
    - **Expected Output:** No errors
    - **Test:** Verify required fields: `yq '.spec.versions[0].schema.openAPIV3Schema.required' definitions/xpostgresqls.yaml`
    - **Expected Output:** Contains `storageSize`
    - _Requirements: 3.1, 3.3, 3.5_
  
  - [ ] 5.2 Create compositions/postgresql-basic.yaml
    - Use pipeline mode with CloudNativePG Cluster resource (apiVersion: postgresql.cnpg.io/v1)
    - Map XRD parameters to CloudNativePG Cluster spec (version→imageName, storageSize→storage.size, instances→instances)
    - Add conditional ScheduledBackup resource when backupEnabled=true
    - **Test:** Verify mode: `yq '.spec.mode' compositions/postgresql-basic.yaml`
    - **Expected Output:** `Pipeline`
    - **Test:** Verify CloudNativePG resource: `yq '.spec.pipeline[0].input.resources[] | select(.name == "cluster") | .base.apiVersion' compositions/postgresql-basic.yaml`
    - **Expected Output:** `postgresql.cnpg.io/v1`
    - **Test:** Render example with backupEnabled=true
    - **Expected Output:** CloudNativePG Cluster with backup configuration and ScheduledBackup resource
    - _Requirements: 2.1, 2.2_
  
  - [ ] 5.3 Create examples/postgresql-example.yaml
    - **Test:** Run `crossplane beta render examples/postgresql-example.yaml definitions/xpostgresqls.yaml compositions/postgresql-basic.yaml`
    - **Expected Output:** CloudNativePG Cluster resource rendered successfully
    - _Requirements: 12.2_

- [ ] 6. Create Dragonfly XRD and Composition
  - [ ] 6.1 Create definitions/xdragonflies.yaml
    - Define schema: memoryLimit, persistence (boolean), replication (object with enabled, replicas)
    - **Test:** Run `kubectl apply --dry-run=client -f definitions/xdragonflies.yaml`
    - **Expected Output:** No errors
    - **Test:** Verify properties exist: `yq '.spec.versions[0].schema.openAPIV3Schema.properties | keys' definitions/xdragonflies.yaml`
    - **Expected Output:** Contains memoryLimit, persistence, replication
    - _Requirements: 3.1, 3.4, 3.5_
  
  - [ ] 6.2 Create compositions/dragonfly-basic.yaml
    - Use pipeline mode with Dragonfly resource (apiVersion: dragonflydb.io/v1alpha1)
    - Map XRD parameters to Dragonfly spec (memoryLimit→resources.limits.memory, replication.replicas→replicas)
    - Add conditional PVC and snapshot configuration when persistence=true
    - **Test:** Verify Dragonfly resource: `yq '.spec.pipeline[0].input.resources[] | select(.name == "dragonfly") | .base.apiVersion' compositions/dragonfly-basic.yaml`
    - **Expected Output:** `dragonflydb.io/v1alpha1`
    - **Test:** Render with persistence=false
    - **Expected Output:** No PVC or snapshot configuration in Dragonfly spec
    - **Test:** Render with replication.enabled=true, replicas=3
    - **Expected Output:** Dragonfly spec.replicas=3
    - _Requirements: 2.1, 2.2_
  
  - [ ] 6.3 Create examples/dragonfly-example.yaml
    - **Test:** Run `crossplane beta render examples/dragonfly-example.yaml definitions/xdragonflies.yaml compositions/dragonfly-basic.yaml`
    - **Expected Output:** Dragonfly resource rendered successfully
    - _Requirements: 12.2_

- [ ] 7. Create Crossplane configuration metadata
  - [ ] 7.1 Create platform/04-apis/crossplane.yaml
    - Add metadata annotations (description, maintainer, source, license)
    - Specify Crossplane version: `>=v1.14.1-0`
    - **Test:** Verify structure: `yq '.apiVersion' platform/04-apis/crossplane.yaml`
    - **Expected Output:** `meta.pkg.crossplane.io/v1alpha1`
    - **Test:** Verify version constraint: `yq '.spec.crossplane.version' platform/04-apis/crossplane.yaml`
    - **Expected Output:** `>=v1.14.1-0`
    - _Requirements: 4.1_
  
  - [ ] 7.2 Add provider dependencies
    - Add provider-kubernetes dependency
    - Add function-conditional-patch-and-transform v0.4.0
    - Add renovate datasource comments
    - **Test:** Verify dependencies: `yq '.spec.dependsOn | length' platform/04-apis/crossplane.yaml`
    - **Expected Output:** At least 2 (provider + function)
    - **Test:** Check renovate comments: `grep 'renovate:' platform/04-apis/crossplane.yaml`
    - **Expected Output:** Renovate datasource comments present
    - _Requirements: 4.2, 4.3, 4.5, 11.4_
  
  - [ ] 7.3 Create .xpkgignore file
    - Exclude: `.github/`, `examples/`, `test/`, `*.md`
    - **Test:** Check file exists: `cat platform/04-apis/.xpkgignore`
    - **Expected Output:** Exclusion patterns listed
    - _Requirements: 4.4_

- [ ] 8. Setup E2E testing with uptest
  - [ ] 8.1 Create test/setup.sh
    - Wait for Crossplane, providers, XRDs to be ready
    - Configure provider-kubernetes ProviderConfig
    - **Test:** Run `bash -n test/setup.sh`
    - **Expected Output:** No syntax errors
    - **Test:** Check script is executable: `ls -l test/setup.sh`
    - **Expected Output:** Execute permission set
    - _Requirements: 6.1, 6.4_
  
  - [ ] 8.2 Add uptest annotations to examples
    - Add `uptest.upbound.io/timeout: "600"` to all examples
    - **Test:** Verify annotations: `yq '.metadata.annotations' examples/*.yaml`
    - **Expected Output:** uptest timeout annotation present
    - _Requirements: 6.2_
  
  - [ ] 8.3 Configure make uptest target in Makefile
    - Add uptest target with setup script reference
    - **Test:** Run `make uptest` (requires local Crossplane)
    - **Expected Output:** Tests run and validate resources reach Ready=True
    - **Note:** May skip if no local Crossplane available, will run in CI
    - _Requirements: 6.1, 6.3, 6.5_

- [ ] 9. Configure provider-kubernetes
  - [ ] 9.1 Create providers/provider-kubernetes.yaml
    - Define Provider resource with version v0.14.0
    - **Test:** Run `kubectl apply --dry-run=client -f providers/provider-kubernetes.yaml`
    - **Expected Output:** No errors
    - **Test:** Verify version: `yq '.spec.package' providers/provider-kubernetes.yaml`
    - **Expected Output:** Contains `provider-kubernetes:v0.14.0`
    - _Requirements: 9.1_
  
  - [ ] 9.2 Create providers/provider-config.yaml
    - Create ProviderConfig using InjectedIdentity
    - **Test:** Run `kubectl apply --dry-run=client -f providers/provider-config.yaml`
    - **Expected Output:** No errors
    - **Test:** Verify credentials source: `yq '.spec.credentials.source' providers/provider-config.yaml`
    - **Expected Output:** `InjectedIdentity`
    - _Requirements: 9.3_
  
  - [ ] 9.3 Create providers/rbac.yaml
    - Create ServiceAccount, ClusterRole (least-privilege), ClusterRoleBinding
    - **Test:** Run `kubectl apply --dry-run=client -f providers/rbac.yaml`
    - **Expected Output:** No errors
    - **Test:** Verify ClusterRole rules: `yq '.rules' providers/rbac.yaml`
    - **Expected Output:** Only necessary permissions (Deployment, Service, HTTPRoute, ScaledObject)
    - _Requirements: 9.1, 9.4_
  
  - [ ] 9.4 Update ArgoCD Application for providers
    - Set sync wave "1" for provider resources
    - **Test:** Verify sync wave: `yq '.metadata.annotations."argocd.argoproj.io/sync-wave"' providers/*.yaml`
    - **Expected Output:** "1"
    - _Requirements: 9.2, 9.5_

- [ ] 10. Update Makefile with all targets
  - [ ] 10.1 Add render target
    - Render all examples with crossplane beta render
    - **Test:** Run `make render`
    - **Expected Output:** All examples render successfully, no errors
    - _Requirements: 8.1_
  
  - [ ] 10.2 Add yamllint target
    - Lint all YAML files in definitions/, compositions/, examples/
    - **Test:** Run `make yamllint`
    - **Expected Output:** No YAML syntax errors
    - _Requirements: 8.2_
  
  - [ ] 10.3 Add build target
    - Use `make build.all` from upbound/build
    - **Test:** Run `make build.all`
    - **Expected Output:** OCI package built in `_output/` directory
    - _Requirements: 5.2, 5.3_
  
  - [ ] 10.4 Verify all Makefile targets work
    - **Test:** Run `make help`
    - **Expected Output:** Lists all available targets
    - **Test:** Run each target: `make render`, `make yamllint`, `make build.all`, `make uptest`
    - **Expected Output:** All targets execute successfully
    - _Requirements: 8.3, 8.5_

- [ ] 11. Setup CI workflows
  - [ ] 11.1 Create .github/workflows/platform-apis-ci.yaml
    - Checkout with submodules: true
    - Run make submodules, yamllint, render, build.all, uptest
    - **Test:** Create test PR and verify workflow runs
    - **Expected Output:** All CI jobs pass (lint, render, build, test)
    - **Test:** Check workflow file syntax: `yamllint .github/workflows/platform-apis-ci.yaml`
    - **Expected Output:** No syntax errors
    - _Requirements: 7.1, 7.2, 7.3, 7.4_
  
  - [ ] 11.2 Create .github/workflows/platform-apis-cd.yaml (optional)
    - Publish packages on merge to main
    - **Test:** Verify workflow triggers on push to main
    - **Expected Output:** Workflow configured correctly
    - _Requirements: 7.5_

- [ ] 12. Configure Renovate for dependency management
  - [ ] 12.1 Create or update .github/renovate.json5
    - Add custom regex managers for Makefile versions (UP_VERSION, UPTEST_VERSION)
    - Configure datasources for Crossplane providers and functions
    - **Test:** Validate JSON5 syntax: `node -e "require('./.github/renovate.json5')"`
    - **Expected Output:** No syntax errors
    - **Test:** Check regex patterns match Makefile: `grep -E 'UP_VERSION|UPTEST_VERSION' Makefile`
    - **Expected Output:** Versions found and match regex pattern
    - _Requirements: 11.2, 11.4, 11.6_
  
  - [ ] 12.2 Add renovate comments to crossplane.yaml
    - Add datasource comments for all dependencies
    - **Test:** Verify comments: `grep 'renovate:' platform/04-apis/crossplane.yaml | wc -l`
    - **Expected Output:** At least 2 comments (provider + function)
    - _Requirements: 11.3_
  
  - [ ] 12.3 Test Renovate configuration (optional)
    - Run Renovate locally or wait for bot to detect
    - **Expected Output:** Renovate detects dependencies and can create PRs
    - _Requirements: 11.2_

- [ ] 13. Create documentation
  - [ ] 13.1 Create platform/04-apis/README.md
    - Document available APIs (WebService, PostgreSQL, Dragonfly)
    - Add quickstart with example claims
    - **Test:** Check README exists and has content: `wc -l platform/04-apis/README.md`
    - **Expected Output:** At least 50 lines of documentation
    - **Test:** Verify examples are included: `grep -c 'apiVersion:' platform/04-apis/README.md`
    - **Expected Output:** At least 3 (one per API)
    - _Requirements: 12.1, 12.5_
  
  - [ ] 13.2 Create docs/references.md
    - List reference projects with URLs and key learnings
    - **Test:** Check file exists: `cat docs/references.md`
    - **Expected Output:** Lists platform-ref-multi-k8s and kubefirst with learnings
    - _Requirements: 12.3_
  
  - [ ] 13.3 Create architecture diagrams
    - Create docs/architecture/platform-flow.md with "Station 1-4" Mermaid diagram showing the agentic feedback loop
    - Create docs/architecture/composition-pipeline.md with Mermaid diagram showing composition pipeline flow
    - **Test:** Verify Mermaid syntax: paste diagrams into https://mermaid.live
    - **Expected Output:** Both diagrams render correctly
    - **Test:** Check Station 1-4 diagram includes: User→Git→CI→ArgoCD→K8s→Robusta→Kagent→Git (feedback loop)
    - **Expected Output:** Complete feedback loop visualized
    - _Requirements: 12.4_
  
  - [ ] 13.4 Document Gateway API usage
    - Explain hardcoded Gateway reference and advantages over Ingress
    - **Test:** Check documentation mentions cilium-gateway: `grep 'cilium-gateway' docs/architecture/*.md`
    - **Expected Output:** Gateway reference documented
    - _Requirements: 10.4_
  
  - [ ] 13.5 Create compatibility matrix
    - Document Crossplane, provider, function versions
    - **Test:** Verify matrix includes all components: `grep -E 'Crossplane|provider-kubernetes|function-conditional' docs/*.md`
    - **Expected Output:** All versions documented
    - _Requirements: 11.5_

- [ ] 14. Update ArgoCD Applications
  - [ ] 14.1 Update platform/04-apis.yaml ArgoCD Application
    - Point source.path to new directory structure
    - Ensure sync waves are correct (providers=1, XRDs/Compositions=2)
    - **Test:** Run `kubectl apply --dry-run=client -f platform/04-apis.yaml`
    - **Expected Output:** No errors
    - **Test:** Verify source path: `yq '.spec.source.path' platform/04-apis.yaml`
    - **Expected Output:** Points to `platform/04-apis/`
    - _Requirements: 1.1_
  
  - [ ] 14.2 Test ArgoCD sync (dry-run first)
    - Run ArgoCD sync with --dry-run
    - **Test:** `argocd app sync platform-04-apis --dry-run`
    - **Expected Output:** Shows resources that would be created/updated, no errors
    - **Test:** Actual sync: `argocd app sync platform-04-apis`
    - **Expected Output:** All resources sync successfully, app becomes Healthy
    - _Requirements: 9.5_

- [ ] 15. End-to-end validation
  - [ ] 15.1 Deploy WebService example
    - Create claim in test namespace
    - **Test:** `kubectl apply -f examples/webservice-example.yaml -n test`
    - **Expected Output:** Claim created
    - **Test:** Wait for Ready: `kubectl wait --for=condition=Ready webservice/test-webservice -n test --timeout=300s`
    - **Expected Output:** Condition met, resources Ready
    - **Test:** Verify resources: `kubectl get deployment,service,httproute -n test`
    - **Expected Output:** Deployment, Service, HTTPRoute exist
    - **Test:** Test with KEDA: Update claim with scaling.enabled=true, verify ScaledObject created
    - **Expected Output:** ScaledObject exists
    - _Requirements: 2.3, 2.4, 10.1_
  
  - [ ] 15.2 Deploy PostgreSQL example
    - Create claim in test namespace
    - **Test:** `kubectl apply -f examples/postgresql-example.yaml -n test`
    - **Expected Output:** Claim created
    - **Test:** Wait for Ready: `kubectl wait --for=condition=Ready postgresql/test-postgresql -n test --timeout=600s`
    - **Expected Output:** CloudNativePG Cluster reaches Ready
    - **Test:** Verify cluster: `kubectl get cluster -n test`
    - **Expected Output:** PostgreSQL cluster running
    - _Requirements: 3.3_
  
  - [ ] 15.3 Deploy Dragonfly example
    - Create claim in test namespace
    - **Test:** `kubectl apply -f examples/dragonfly-example.yaml -n test`
    - **Expected Output:** Claim created
    - **Test:** Wait for Ready: `kubectl wait --for=condition=Ready dragonfly/test-dragonfly -n test --timeout=300s`
    - **Expected Output:** Dragonfly instance Ready
    - **Test:** Verify instance: `kubectl get pods -n test -l app=dragonfly`
    - **Expected Output:** Dragonfly pod running
    - _Requirements: 3.4_
  
  - [ ] 15.4 Verify deletion ordering with Usage resources
    - Attempt to delete parent resource while children exist
    - **Test:** `kubectl delete webservice/test-webservice -n test`
    - **Expected Output:** If Usage resources configured, deletion blocked until children removed
    - **Test:** Delete children first, then parent
    - **Expected Output:** Clean deletion in correct order
    - _Requirements: 2.5_
  
  - [ ] 15.5 Cleanup test resources
    - Delete all test claims
    - **Test:** `kubectl delete -f examples/*.yaml -n test`
    - **Expected Output:** All resources deleted cleanly
    - **Test:** Verify cleanup: `kubectl get all -n test`
    - **Expected Output:** No resources remaining

- [ ] 16. Cleanup old structure
  - Remove old platform/04-apis/compositions/webservice.yaml (if not already moved)
  - Remove old platform/04-apis/provider-config.yaml (if not already moved)
  - Update any documentation references to old structure
  - **Test:** Verify old files removed: `ls platform/04-apis/compositions/webservice.yaml`
  - **Expected Output:** File not found
  - **Test:** Search for old references: `grep -r 'compositions/webservice.yaml' docs/`
  - **Expected Output:** No references to old structure
  - _Requirements: 1.1_

- [ ] 17. Final validation
  - **Test:** Run full CI pipeline locally: `make submodules && make yamllint && make render && make build.all && make uptest`
  - **Expected Output:** All steps pass successfully
  - **Test:** Verify ArgoCD shows all apps Healthy: `argocd app list | grep platform-04-apis`
  - **Expected Output:** Status: Healthy, Synced
  - **Test:** Verify all XRDs installed: `kubectl get xrd`
  - **Expected Output:** xwebservices, xpostgresqls, xdragonflies present
  - **Test:** Verify providers healthy: `kubectl get providers`
  - **Expected Output:** provider-kubernetes Healthy=True
  - **Test:** Create and delete a test claim end-to-end
  - **Expected Output:** Full lifecycle works (create → ready → delete → cleanup)
