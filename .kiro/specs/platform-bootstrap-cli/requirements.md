# Requirements Document

## Introduction

This document defines the requirements for a CLI tool that orchestrates Day 0 bootstrap of the agentic-native infrastructure platform. The CLI enforces correct sequencing, validates prerequisites, provides interactive progress feedback, and ensures idempotent operations.

**Scope:** Bootstrap orchestration, pre-flight validation, progress tracking, error handling, and logging. Runtime platform operations (handled by Kagent) and Crossplane API structure (separate spec) are out of scope.

## Glossary

- **Bootstrap**: Day 0 process of installing ArgoCD and syncing platform components
- **Pre-flight Check**: Validation performed before bootstrap starts
- **Idempotent**: Safe to re-run without causing errors or duplicate resources
- **Sync Wave**: ArgoCD annotation controlling deployment order
- **Platform CLI**: Command-line tool for bootstrap operations
- **GitOps Repository**: Git repository containing platform manifests
- **Talos Cluster**: Kubernetes cluster running Talos Linux OS
- **GitShim**: Abstraction layer for Git provider operations (GitHub, GitLab)
- **Detokenization**: Process of replacing template variables with actual values
- **Deploy Token**: Credential allowing ArgoCD to access Git repository
- **State Backup**: Kubernetes Secret containing bootstrap state for disaster recovery

## Requirements

### Requirement 1: CLI Command Structure

**User Story:** As a Platform Operator, I want a simple CLI with clear commands, so that I can bootstrap and manage the platform without memorizing complex procedures.

**Reference Pattern:** ✅ Kubefirst CLI structure
- Root command with subcommands
- Flags for configuration
- Help text and examples

#### Acceptance Criteria

1. WHEN invoking the CLI, THE CLI SHALL provide a root command `platform` with subcommands: `bootstrap`, `validate`, `status`, `destroy`
2. WHEN running bootstrap, THE Bootstrap Command SHALL accept flags: `--repo`, `--env`, `--cluster-name`, `--dry-run`
3. WHEN requesting help, THE CLI SHALL display usage examples and flag descriptions
4. WHERE configuration is needed, THE CLI SHALL support environment variables prefixed with `PLATFORM_`
5. WHEN executing commands, THE CLI SHALL exit with appropriate status codes (0 for success, non-zero for errors)

### Requirement 2: Pre-flight Validation

**User Story:** As a Platform Operator, I want pre-flight checks before bootstrap starts, so that I can fix issues early and avoid partial failures.

**Reference Pattern:** ✅ Kubefirst validation pattern
- Git credential validation (`internal/gitShim/gitShim.go`)
- Cluster connectivity checks
- Prerequisite verification

#### Acceptance Criteria

1. WHEN running bootstrap, THE CLI SHALL validate Talos cluster is reachable via kubeconfig
2. WHEN validating Git, THE CLI SHALL verify Git provider credentials (token) are valid and have required permissions
3. WHEN checking prerequisites, THE CLI SHALL verify required tools are installed: `kubectl`, `talosctl`, `argocd`, `git`
4. WHERE DNS is configured, THE CLI SHALL validate DNS records resolve correctly
5. WHEN validation fails, THE CLI SHALL display actionable error messages with remediation steps

### Requirement 3: Bootstrap Orchestration

**User Story:** As a Platform Operator, I want automated bootstrap orchestration, so that the platform deploys in the correct sequence without manual intervention.

**Reference Pattern:** ✅ Kubefirst provision pattern
- Step-by-step orchestration (`internal/provision/provision.go`)
- Wait for readiness between steps
- Handle dependencies

#### Acceptance Criteria

1. WHEN bootstrapping, THE CLI SHALL execute steps in order: Validate Git → Setup Git Authentication → Install ArgoCD → Configure Secrets → Deploy Platform Applications → Wait for Sync → Backup State
2. WHEN installing ArgoCD, THE CLI SHALL apply ArgoCD manifests and wait for pods to be ready
3. WHEN configuring Git authentication, THE CLI SHALL generate SSH keys or deploy tokens and register them with the Git provider for ArgoCD access
4. WHEN configuring secrets, THE CLI SHALL create necessary secrets in the ArgoCD namespace (Git credentials, external secrets)
5. WHEN deploying platform, THE CLI SHALL create ArgoCD Applications for platform layers (foundation, observability, intelligence, apis)
6. WHERE sync waves exist, THE CLI SHALL respect ArgoCD sync wave ordering (providers before compositions)

### Requirement 4: Idempotent Operations

**User Story:** As a Platform Operator, I want idempotent bootstrap operations, so that I can safely re-run the CLI after failures without causing errors.

**Reference Pattern:** ✅ Kubefirst cluster state checking
- Check existing resources before creating
- Skip completed steps
- Resume from failure point

#### Acceptance Criteria

1. WHEN bootstrapping, THE CLI SHALL check if ArgoCD is already installed before attempting installation
2. WHEN checking state, THE CLI SHALL verify if platform Applications already exist
3. WHEN resuming, THE CLI SHALL skip completed steps and continue from the last incomplete step
4. WHERE resources exist, THE CLI SHALL update them if configuration changed, not fail with "already exists" errors
5. WHEN re-running, THE CLI SHALL produce the same end state regardless of how many times it runs

### Requirement 5: Interactive Progress Feedback

**User Story:** As a Platform Operator, I want visual progress feedback during bootstrap, so that I can monitor status and identify issues quickly.

**Reference Pattern:** ✅ Kubefirst BubbleTea UI
- Step-by-step progress display
- Emoji indicators for status
- Real-time updates

#### Acceptance Criteria

1. WHEN bootstrapping, THE CLI SHALL display current step with emoji indicators (⏳ in progress, ✅ complete, ❌ failed)
2. WHEN waiting for resources, THE CLI SHALL show waiting status with resource name and namespace
3. WHEN errors occur, THE CLI SHALL display error messages inline with the failed step
4. WHERE multiple operations run, THE CLI SHALL update progress in real-time
5. WHEN bootstrap completes, THE CLI SHALL display summary with access URLs and credentials

### Requirement 6: Structured Logging

**User Story:** As a Platform Operator, I want structured logs saved to files, so that I can troubleshoot issues and audit bootstrap operations.

**Reference Pattern:** ✅ Kubefirst dual logging
- Console output for humans
- File logs for debugging
- Structured log format

#### Acceptance Criteria

1. WHEN running bootstrap, THE CLI SHALL write logs to `~/.platform/logs/bootstrap-<timestamp>.log`
2. WHEN logging, THE Logs SHALL use structured format with timestamp, level, and message
3. WHEN displaying console output, THE CLI SHALL show human-readable progress (not raw logs)
4. WHERE errors occur, THE CLI SHALL log full error details and stack traces to file
5. WHEN bootstrap completes, THE CLI SHALL display log file location

### Requirement 7: Crossplane Provider Validation

**User Story:** As a Platform Operator, I want validation that Crossplane providers are healthy, so that compositions can deploy successfully.

**Reference Pattern:** ✅ Platform-ref-multi-k8s provider setup
- Wait for provider pods
- Verify ProviderConfig
- Check RBAC

#### Acceptance Criteria

1. WHEN platform APIs sync, THE CLI SHALL wait for provider-kubernetes pods to be ready
2. WHEN validating providers, THE CLI SHALL verify ProviderConfig exists and is configured
3. WHEN checking RBAC, THE CLI SHALL verify provider ServiceAccount has necessary permissions
4. WHERE providers fail, THE CLI SHALL display provider pod logs and status
5. WHEN providers are healthy, THE CLI SHALL proceed to composition deployment

### Requirement 8: Gateway API Validation

**User Story:** As a Platform Operator, I want validation that Gateway API is configured, so that HTTPRoute compositions work correctly.

**Reference Pattern:** ⚠️ ASSUMPTION - Platform-specific (Cilium + Gateway API)

#### Acceptance Criteria

1. WHEN validating foundation, THE CLI SHALL verify Gateway API CRDs are installed
2. WHEN checking Gateway, THE CLI SHALL verify `cilium-gateway` exists in `default` namespace
3. WHEN validating Gateway, THE CLI SHALL check Gateway status is `Programmed`
4. WHERE Gateway is missing, THE CLI SHALL display error with instructions to deploy foundation layer first
5. WHEN Gateway is ready, THE CLI SHALL allow WebService compositions with HTTPRoute

### Requirement 9: Configuration Management and State Backup

**User Story:** As a Platform Operator, I want configuration persistence and disaster recovery, so that I can resume multi-step workflows and restore platform state after failures.

**Reference Pattern:** ✅ Kubefirst state management
- Config directory in home (`~/.k1/`)
- Persist state between runs
- Backup state to cluster (`internal/utilities/utilities.go`)

#### Acceptance Criteria

1. WHEN bootstrapping, THE CLI SHALL create `~/.platform/` directory for configuration and logs
2. WHEN tracking state, THE CLI SHALL write bootstrap state to `~/.platform/state.yaml`
3. WHEN resuming, THE CLI SHALL read state file to determine completed steps
4. WHERE configuration changes, THE CLI SHALL update state file
5. WHEN bootstrap completes, THE CLI SHALL export platform state as a Kubernetes Secret named `platform-initial-state` in the `argocd` namespace for disaster recovery

### Requirement 10: Error Handling and Recovery

**User Story:** As a Platform Operator, I want clear error messages with recovery guidance, so that I can fix issues and retry bootstrap.

**Reference Pattern:** ✅ Kubefirst error wrapping
- Context-rich errors
- Remediation hints
- Graceful failures

#### Acceptance Criteria

1. WHEN errors occur, THE CLI SHALL wrap errors with context describing what operation failed
2. WHEN displaying errors, THE CLI SHALL provide remediation hints (e.g., "Check kubeconfig is valid")
3. WHEN operations fail, THE CLI SHALL exit gracefully without leaving resources in inconsistent state
4. WHERE retries are possible, THE CLI SHALL suggest re-running the command
5. WHEN logging errors, THE CLI SHALL include full error details and stack traces in log file

### Requirement 11: Validation Mode

**User Story:** As a Platform Operator, I want validation mode, so that I can verify prerequisites and configuration without executing bootstrap.

**Reference Pattern:** ⚠️ PARTIAL - Kubefirst has validation but not full dry-run
- Pre-flight checks only
- No mock execution

#### Acceptance Criteria

1. WHEN running with `--validate-only`, THE CLI SHALL perform all pre-flight checks without executing bootstrap
2. WHEN in validation mode, THE CLI SHALL verify cluster connectivity, Git credentials, and prerequisites
3. WHEN validating, THE CLI SHALL check if required tools are installed and accessible
4. WHERE configuration errors exist, THE CLI SHALL display them with remediation steps
5. WHEN validation completes, THE CLI SHALL exit with summary of checks passed/failed

### Requirement 12: Platform Status Command

**User Story:** As a Platform Operator, I want a status command, so that I can check platform health and component readiness.

**Reference Pattern:** ✅ Kubefirst cluster status checking

#### Acceptance Criteria

1. WHEN running `platform status`, THE CLI SHALL display ArgoCD Application sync status for all platform layers
2. WHEN checking health, THE CLI SHALL show pod status for critical components (ArgoCD, Crossplane, Cilium)
3. WHEN displaying status, THE CLI SHALL use color coding (green for healthy, yellow for degraded, red for failed)
4. WHERE issues exist, THE CLI SHALL highlight failed components with error messages
5. WHEN status is healthy, THE CLI SHALL display "Platform is healthy" with access URLs

### Requirement 13: Platform Destroy Command

**User Story:** As a Platform Operator, I want a destroy command, so that I can cleanly tear down the platform for testing or decommissioning.

**Reference Pattern:** ✅ Kubefirst destroy pattern

#### Acceptance Criteria

1. WHEN running `platform destroy`, THE CLI SHALL prompt for confirmation before proceeding
2. WHEN destroying, THE CLI SHALL delete ArgoCD Applications in reverse order (apis, intelligence, observability, foundation)
3. WHEN cleaning up, THE CLI SHALL delete ArgoCD installation
4. WHERE state exists, THE CLI SHALL remove `~/.platform/state.yaml`
5. WHEN destroy completes, THE CLI SHALL display "Platform destroyed successfully"

### Requirement 14: Compatibility with Crossplane API Spec

**User Story:** As a Platform Developer, I want the bootstrap CLI to work seamlessly with the Crossplane API structure, so that both specs are compatible and complementary.

**Reference Pattern:** ✅ Existing `.kiro/specs/repo-restructure-refactor/`

#### Acceptance Criteria

1. WHEN deploying platform APIs, THE CLI SHALL create ArgoCD Application pointing to `platform/04-apis/` directory
2. WHEN validating Crossplane, THE CLI SHALL use `crossplane beta render` on examples (same as CI)
3. WHEN checking providers, THE CLI SHALL respect sync wave "1" for providers before compositions
4. WHERE Gateway API is used, THE CLI SHALL validate `cilium-gateway` exists before allowing HTTPRoute compositions
5. WHEN bootstrap completes, THE CLI SHALL verify all XRDs and Compositions are synced and healthy

### Requirement 15: GitOps-First Architecture

**User Story:** As a Platform Architect, I want the CLI to respect GitOps principles, so that all platform state is managed via Git and ArgoCD.

**Reference Pattern:** ✅ Platform overview - GitOps-centric design

#### Acceptance Criteria

1. WHEN bootstrapping, THE CLI SHALL NOT apply platform manifests directly via kubectl (except ArgoCD installation)
2. WHEN deploying platform, THE CLI SHALL create ArgoCD Applications that reference Git repository
3. WHEN making changes, THE CLI SHALL instruct users to commit changes to Git, not apply directly
4. WHERE ArgoCD manages resources, THE CLI SHALL wait for ArgoCD sync, not force sync
5. WHEN bootstrap completes, THE CLI SHALL display message "Platform is now managed by ArgoCD via Git"

### Requirement 16: Git Provider Abstraction (GitShim)

**User Story:** As a Platform Developer, I want Git provider operations abstracted, so that the CLI works with both GitHub and GitLab without provider-specific code.

**Reference Pattern:** ✅ Kubefirst GitShim pattern
- Abstraction layer (`internal/gitShim/gitShim.go`)
- Normalize GitHub and GitLab operations
- Handle authentication differences

#### Acceptance Criteria

1. WHEN interacting with Git providers, THE CLI SHALL use a GitShim abstraction layer
2. WHEN validating credentials, THE GitShim SHALL support both GitHub tokens and GitLab tokens
3. WHEN creating deploy tokens, THE GitShim SHALL handle provider-specific API differences
4. WHERE SSH keys are needed, THE GitShim SHALL generate and register keys with the appropriate provider
5. WHEN adding webhooks, THE GitShim SHALL normalize webhook creation across providers

### Requirement 17: Telemetry and Usage Tracking

**User Story:** As a Platform Maintainer, I want optional telemetry, so that I can track bootstrap success rates and identify common failure points.

**Reference Pattern:** ✅ Kubefirst Segment integration
- Track step completion (`internal/segment/segment.go`)
- Anonymized usage data
- Opt-out capability

#### Acceptance Criteria

1. WHEN bootstrapping, THE CLI SHALL track step completion and failure events
2. WHEN telemetry is enabled, THE CLI SHALL send anonymized usage data (no PII, no cluster details)
3. WHEN users opt out, THE CLI SHALL respect `--no-telemetry` flag or `PLATFORM_TELEMETRY=false` environment variable
4. WHERE errors occur, THE CLI SHALL track error types (not error messages) for debugging patterns
5. WHEN telemetry is disabled, THE CLI SHALL function identically with no degradation
