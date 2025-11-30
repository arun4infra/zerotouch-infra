--- START OF FILE requirements.md ---

# Requirements Document

## Introduction

This document defines the requirements for restructuring the `platform/04-apis/` directory to follow Crossplane best practices learned from platform-ref-multi-k8s. The goal is to create a well-organized structure for platform APIs (XRDs and Compositions) with proper CI/validation workflows.

**Scope:** Repository organization for Crossplane APIs, CI/validation workflows, and configuration packaging. Operational concerns (upgrades, capacity planning, tenant onboarding) are out of scope.

## Glossary

- **XRD**: Crossplane Composite Resource Definition - defines the API schema
- **Composition**: Crossplane resource that implements an XRD by composing managed resources
- **Composition Pipeline**: Crossplane feature using functions for conditional logic and transformations
- **Configuration Package**: Metadata wrapper defining dependencies and versions (logical grouping, not necessarily OCI artifact)
- **Gateway API**: Modern Kubernetes networking API (replaces Ingress)
- **Platform APIs**: Self-service APIs for WebService, PostgreSQL, Dragonfly provisioning

## Requirements

### Requirement 1: Platform APIs Directory Restructuring

**User Story:** As a Platform Developer, I want the `platform/04-apis/` directory organized following Crossplane best practices, so that XRDs, Compositions, and providers are easy to find and maintain.

**Reference Pattern:** ✅ `docs/dev/repos/platform-ref-multi-k8s/`
- Directory: `apis/` contains `definition.yaml` and `composition.yaml`
- Directory: `examples/` contains example claims
- File: `crossplane.yaml` at root for package metadata

#### Acceptance Criteria

1. WHEN organizing the APIs directory, THE Structure SHALL use subdirectories: `definitions/`, `compositions/`, `examples/`, `providers/`
2. WHEN storing XRDs, THE XRDs SHALL be placed in `platform/04-apis/definitions/` with one file per resource type
3. WHEN storing Compositions, THE Compositions SHALL be placed in `platform/04-apis/compositions/` with one file per composition
4. WHEN providing examples, THE Example Claims SHALL be placed in `platform/04-apis/examples/` for testing and documentation
5. WHEN configuring providers, THE Provider Configs SHALL be placed in `platform/04-apis/providers/`

### Requirement 2: Crossplane Composition Pipeline Pattern

**User Story:** As a Platform Architect, I want Compositions to use pipeline mode with functions, so that I can implement conditional logic for optional features (KEDA scaling, public exposure).

**Reference Pattern:** ✅ `docs/dev/repos/platform-ref-multi-k8s/apis/composition.yaml`
- Line 6: `mode: Pipeline`
- Lines 7-12: `pipeline` with `functionRef` to `function-conditional-patch-and-transform`
- Line 17+: Conditional resources using `condition:` fields

#### Acceptance Criteria

1. WHEN creating Compositions, THE Compositions SHALL use `mode: Pipeline` instead of legacy patch-and-transform mode
2. WHEN implementing conditional logic, THE Compositions SHALL use `function-conditional-patch-and-transform` for parameter-based resource creation
3. WHEN defining WebService Compositions, THE Compositions SHALL support conditional KEDA ScaledObject creation based on `spec.scaling.enabled` parameter
4. WHEN defining WebService Compositions, THE Compositions SHALL support conditional HTTPRoute creation based on `spec.public` parameter
5. WHERE Compositions reference child resources (like GitOps or Observability), THE Compositions SHALL inject `Usage` resources to prevent the parent from being deleted while children exist (Deletion Ordering - CRITICAL for multi-tenant safety).

### Requirement 3: Platform API Definitions (XRDs)

**User Story:** As a Platform User, I want comprehensive XRD definitions with validation, so that I have clear, type-safe APIs for provisioning resources.

**Reference Pattern:** ✅ `docs/dev/repos/platform-ref-multi-k8s/apis/definition.yaml`
- Lines 1-16: XRD metadata with `claimNames` and `connectionSecretKeys`
- Lines 18-150: Detailed OpenAPI v3 schema with descriptions, types, enums, defaults, validation

#### Acceptance Criteria

1. WHEN creating XRDs, THE XRDs SHALL include detailed OpenAPI v3 schemas with property descriptions, types, enums, and default values
2. WHEN defining WebService XRDs, THE Schema SHALL include parameters for: image, port, replicas, scaling (KEDA), public (HTTPRoute), observability (OTEL)
3. WHEN defining PostgreSQL XRDs, THE Schema SHALL include parameters for: version, storageSize, backupEnabled, monitoring
4. WHEN defining Dragonfly XRDs, THE Schema SHALL include parameters for: memoryLimit, persistence, replication
5. WHERE validation is needed, THE Schemas SHALL use OpenAPI validation rules (pattern, minimum, maximum, required fields)

### Requirement 4: Crossplane Configuration Metadata

**User Story:** As a Platform Operator, I want proper Crossplane configuration metadata, so that platform APIs are versioned and dependencies are clear, even if not distributed via OCI.

**Reference Pattern:** ✅ `docs/dev/repos/platform-ref-multi-k8s/crossplane.yaml`
- Lines 1-36: Package metadata with annotations (description, maintainer, source, license)
- Lines 38-39: Crossplane version constraints
- Lines 40-56: Dependencies with pinned versions

#### Acceptance Criteria

1. WHEN creating the package, THE Package SHALL include `platform/04-apis/crossplane.yaml` with metadata and version constraints
2. WHEN specifying dependencies, THE Dependencies SHALL include `provider-kubernetes` for in-cluster resource management
3. WHEN specifying dependencies, THE Dependencies SHALL include `function-conditional-patch-and-transform` version `v0.4.0`
4. WHERE files should be excluded, THE Package SHALL use `.xpkgignore` to exclude `.github/`, `examples/`, test files
5. WHEN versioning, THE Package SHALL use semantic versioning and Renovate comments for dependency updates

### Requirement 5: Standardized Build System

**User Story:** As a Platform Developer, I want a standardized build system equivalent to upbound/build, so that I can build, test, and publish Crossplane packages consistently.

**Reference Pattern:** ✅ `docs/dev/repos/platform-ref-multi-k8s/`
- File: `.gitmodules` - upbound/build submodule
- File: `Makefile` lines 9, 18, 28, 32-33: Includes from `build/makelib/`
- Provides: `common.mk`, `k8s_tools.mk`, `xpkg.mk`, `local.xpkg.mk`, `controlplane.mk`

#### Acceptance Criteria

1. WHEN setting up the build system, THE Build System SHALL use upbound/build submodule or equivalent makelib includes
2. WHEN building packages, THE Build System SHALL provide `make build.all` target for creating OCI images
3. WHEN testing locally, THE Build System SHALL provide `make controlplane.up` to spin up local Crossplane for testing
4. WHERE package publishing is needed, THE Build System SHALL provide `make publish` target for pushing to registries
5. WHEN managing tools, THE Build System SHALL auto-install required tools (crossplane CLI, up CLI, kubectl) via makelib

### Requirement 6: End-to-End Testing with Uptest

**User Story:** As a Platform Operator, I want automated E2E tests that validate resources reach Ready=True, so that I have confidence in production deployments.

**Reference Pattern:** ✅ `docs/dev/repos/platform-ref-multi-k8s/`
- File: `Makefile` lines 56-59: `uptest` target with E2E testing
- File: `test/setup.sh` - Provider setup for E2E tests
- File: `.github/workflows/e2e.yaml` - E2E workflow

#### Acceptance Criteria

1. WHEN running E2E tests, THE Test Framework SHALL use `uptest` (v0.11.1 or compatible) to validate resource lifecycle
2. WHEN testing compositions, THE Tests SHALL verify that all composed resources reach `Ready=True` status
3. WHEN setting up tests, THE Test Setup SHALL configure providers and credentials using `test/setup.sh` pattern
4. WHERE cloud credentials are needed, THE Tests SHALL use environment variables or GitHub Secrets for provider authentication
5. WHEN E2E tests complete, THE Tests SHALL clean up all created resources to avoid resource leaks

### Requirement 7: Continuous Integration and Validation

**User Story:** As a Platform Developer, I want automated CI that validates Crossplane configurations, so that errors are caught before deployment.

**Reference Pattern:** ✅ `docs/dev/repos/platform-ref-multi-k8s/`
- File: `.github/workflows/ci.yaml` - Build and publish with submodules
- File: `.github/workflows/yamllint.yaml` - YAML linting
- File: `Makefile` lines 68-75: `render` and `yamllint` targets

#### Acceptance Criteria

1. WHEN validating compositions, THE CI Pipeline SHALL run `crossplane beta render` on all examples to verify resource generation
2. WHEN validating YAML, THE CI Pipeline SHALL run `yamllint` on `platform/04-apis/` directory
3. WHEN building packages, THE CI Pipeline SHALL use `make build.all` from upbound/build to create OCI images
4. WHERE E2E tests are enabled, THE CI Pipeline SHALL run `make uptest` to validate resource lifecycle
5. WHEN CI passes, THE Pipeline SHALL publish packages to registry on merge to main branch

### Requirement 8: Testing and Development Workflow

**User Story:** As a Platform Developer, I want local testing tools, so that I can validate changes before pushing to CI.

**Reference Pattern:** ✅ `docs/dev/repos/platform-ref-multi-k8s/Makefile`
- Lines 68-71: `render` target
- Lines 72-75: `yamllint` target

#### Acceptance Criteria

1. WHEN testing locally, THE Makefile SHALL provide a `render` target that runs `crossplane beta render` on all examples
2. WHEN linting locally, THE Makefile SHALL provide a `yamllint` target that validates YAML syntax
3. WHEN validating schemas, THE Workflow SHALL ensure XRDs have valid OpenAPI v3 schemas
4. WHERE provider setup is needed, THE Test Scripts SHALL follow `test/setup.sh` pattern for provider configuration
5. WHEN examples are added, THE Examples SHALL be tested with the `render` target before committing

### Requirement 9: Crossplane Provider Configuration

**User Story:** As a Platform Operator, I want proper provider configurations with RBAC, so that Crossplane can securely manage Kubernetes resources.

**Reference Pattern:** ✅ `docs/dev/repos/platform-ref-multi-k8s/test/setup.sh` lines 80-120

#### Acceptance Criteria

1. WHEN configuring provider-kubernetes, THE Configuration SHALL use a dedicated ServiceAccount with least-privilege RBAC
2. WHEN deploying providers, THE Deployment SHALL use ArgoCD with sync wave "1" to ensure providers are ready before compositions
3. WHEN creating ProviderConfigs, THE Configs SHALL reference appropriate credentials (ServiceAccount for in-cluster, Secrets for external)
4. WHERE RBAC is required, THE RBAC SHALL grant only necessary permissions for resource types used in compositions
5. WHEN providers are installed, THE Installation SHALL wait for provider pods to be healthy before applying compositions

### Requirement 10: Gateway API Integration

**User Story:** As a Platform Developer, I want WebService compositions to use Gateway API, so that routing leverages Cilium-native networking.

**Reference Pattern:** ⚠️ ASSUMPTION - Platform-specific (Cilium + Gateway API). Reference projects use cloud load balancers.

#### Acceptance Criteria

1. WHEN creating WebService compositions, THE Compositions SHALL generate HTTPRoute resources instead of Ingress
2. WHEN configuring routing, THE HTTPRoute SHALL reference the existing Cilium Gateway by hardcoding `name: cilium-gateway` and `namespace: default` in the parentRefs field
3. WHERE TLS is required, THE HTTPRoute SHALL support TLS configuration via Gateway API
4. WHEN documenting, THE Documentation SHALL explain Gateway API advantages over legacy Ingress and clarify that the Gateway reference is a fixed platform constant
5. WHEN testing, THE Examples SHALL include HTTPRoute configuration with user-provided hostname parameter

### Requirement 11: Platform Versioning and Dependency Management

**User Story:** As a Platform Operator, I want clear versioning with automated updates, so that dependencies stay current and secure.

**Reference Pattern:** ✅ `docs/dev/repos/platform-ref-multi-k8s/`
- File: `crossplane.yaml` line 38: `version: ">=v1.14.1-0"`
- File: `.github/renovate.json5` - Renovate config
- Lines 42-56: Renovate datasource comments

#### Acceptance Criteria

1. WHEN specifying Crossplane version, THE Configuration SHALL use version constraints (e.g., `>=v1.14.1-0`)
2. WHEN managing dependencies, THE Repository SHALL use Renovate with `.github/renovate.json5` for automated updates
3. WHEN pinning versions, THE Dependencies SHALL use semantic versioning with renovate datasource comments
4. WHEN configuring Renovate, THE Configuration SHALL use custom regex managers (matching `.github/renovate.json5` patterns) to automate version bumps in the `Makefile` and annotated fields in `crossplane.yaml` (REQUIRED for release automation)
5. WHEN documenting versions, THE Documentation SHALL maintain a compatibility matrix
6. WHERE tool versions are defined in Makefile, THE Renovate Regex Managers SHALL detect and update versions automatically (e.g., `UP_VERSION`, `UPTEST_VERSION`, `CROSSPLANE_VERSION`)

### Requirement 12: Documentation and Examples

**User Story:** As a Platform User, I want clear documentation and working examples, so that I can understand how to use platform APIs.

**Reference Pattern:** ⚠️ PARTIAL - `docs/dev/repos/platform-ref-multi-k8s/README.md` shows structure

#### Acceptance Criteria

1. WHEN documenting APIs, THE Documentation SHALL create `platform/04-apis/README.md` explaining available APIs and usage
2. WHEN providing examples, THE Examples SHALL include working claims for WebService, PostgreSQL, and Dragonfly
3. WHEN documenting patterns, THE Documentation SHALL create `docs/references.md` listing reference projects and learnings
4. WHERE architecture decisions are made, THE Documentation SHALL include Mermaid diagrams in `docs/architecture/`
5. WHEN onboarding users, THE README SHALL include quickstart instructions for creating claims