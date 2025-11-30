# Design Document

## Overview

This design document outlines the technical approach for building a CLI tool that orchestrates Day 0 bootstrap of the agentic-native infrastructure platform. The CLI follows Kubefirst architectural patterns while respecting the GitOps-first, YAML-centric nature of the platform.

**Key Design Principles:**
- Minimal Go wrapper around YAML manifests (not a Go monolith)
- GitOps-first: ArgoCD manages platform, CLI only bootstraps
- Idempotent: safe to re-run at any point
- Compatible with Crossplane API spec (separate concern)
- AI-friendly: structured logs and state for Kagent integration

## Architecture

### High-Level Flow

```mermaid
graph TD
    A[User runs: platform bootstrap] --> B[Pre-flight Validation]
    B --> C{Validation Pass?}
    C -->|No| D[Display Errors & Exit]
    C -->|Yes| E[Setup Git Authentication]
    E --> F[Install ArgoCD]
    F --> G[Configure Secrets]
    G --> H[Deploy Platform Apps]
    H --> I[Wait for Sync]
    I --> J[Validate Components]
    J --> K[Backup State to Cluster]
    K --> L[Display Success Message]
```

### Component Architecture

```
platform-cli/
├── cmd/
│   ├── root.go              # Root command
│   ├── bootstrap.go         # Bootstrap command
│   ├── validate.go          # Validation command
│   ├── status.go            # Status command
│   └── destroy.go           # Destroy command
├── internal/
│   ├── bootstrap/
│   │   ├── orchestrator.go  # Main bootstrap orchestration
│   │   └── steps.go         # Individual bootstrap steps
│   ├── gitshim/
│   │   ├── interface.go     # Git provider interface
│   │   ├── github.go        # GitHub implementation
│   │   └── gitlab.go        # GitLab implementation
│   ├── validation/
│   │   ├── preflight.go     # Pre-flight checks
│   │   └── validators.go    # Individual validators
│   ├── progress/
│   │   ├── stepper.go       # Progress tracking
│   │   └── display.go       # Terminal UI
│   ├── state/
│   │   ├── manager.go       # State persistence
│   │   └── backup.go        # Cluster state backup
│   ├── telemetry/
│   │   └── tracker.go       # Usage tracking
│   └── k8s/
│       ├── client.go        # Kubernetes client wrapper
│       └── wait.go          # Resource readiness checks
└── main.go
```


### Technology Stack

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| CLI Framework | Cobra | Industry standard, used by Kubefirst |
| Configuration | Viper | Integrates with Cobra, supports env vars |
| Terminal UI | BubbleTea (optional) | Rich progress display, used by Kubefirst |
| Logging | Zerolog | Structured logging, fast performance |
| Kubernetes Client | client-go | Official Kubernetes Go client |
| Git Operations | go-git | Pure Go git implementation |
| HTTP Client | Standard library | Simple API calls to Git providers |

## Components and Interfaces

### 1. CLI Commands (cmd/)

**Purpose:** Define user-facing commands and flags

**Bootstrap Command:**
```go
type BootstrapFlags struct {
    Repo        string // GitOps repository URL
    Env         string // Environment (production, staging)
    ClusterName string // Cluster identifier
    GitProvider string // github or gitlab
    GitToken    string // Git provider token
    ValidateOnly bool  // Run validation only
    NoTelemetry bool   // Disable telemetry
}
```

**Key Design Decisions:**
- Use Cobra for command structure (matches Kubefirst)
- Support both flags and environment variables
- Validate flags before executing commands
- Use Viper for configuration management

### 2. Bootstrap Orchestrator (internal/bootstrap/)

**Purpose:** Coordinate bootstrap steps in correct sequence

**Interface:**
```go
type Orchestrator struct {
    config      *Config
    gitShim     gitshim.Provider
    k8sClient   *k8s.Client
    stepper     *progress.Stepper
    stateManager *state.Manager
    telemetry   *telemetry.Tracker
}

func (o *Orchestrator) Bootstrap(ctx context.Context) error {
    // Execute steps in order
    steps := []Step{
        o.ValidatePrerequisites,
        o.SetupGitAuthentication,
        o.InstallArgoCD,
        o.ConfigureSecrets,
        o.DeployPlatformApps,
        o.WaitForSync,
        o.ValidateComponents,
        o.BackupState,
    }
    
    for _, step := range steps {
        if err := o.executeStep(ctx, step); err != nil {
            return err
        }
    }
    
    return nil
}
```

**Key Design Decisions:**
- Sequential step execution (not parallel)
- Each step is idempotent
- State tracked between steps
- Errors wrapped with context


### 3. GitShim Abstraction (internal/gitshim/)

**Purpose:** Abstract Git provider operations for GitHub and GitLab

**Interface:**
```go
type Provider interface {
    // ValidateCredentials checks if token has required permissions
    ValidateCredentials(ctx context.Context) error
    
    // CreateDeployToken creates a deploy token for ArgoCD
    CreateDeployToken(ctx context.Context, repo string) (*DeployToken, error)
    
    // GenerateSSHKey generates and registers SSH key with provider
    GenerateSSHKey(ctx context.Context, repo string) (*SSHKey, error)
    
    // GetRepository retrieves repository information
    GetRepository(ctx context.Context, repo string) (*Repository, error)
}

type DeployToken struct {
    Username string
    Token    string
}

type SSHKey struct {
    PublicKey  string
    PrivateKey string
}
```

**Implementation Strategy:**
- GitHub: Use GitHub API v3 for deploy keys
- GitLab: Use GitLab API v4 for deploy tokens
- Both: Generate SSH keys using crypto/ssh
- Store credentials in Kubernetes Secrets

**Key Design Decisions:**
- Interface-based design for testability
- Provider selected based on repository URL
- Credentials stored securely in cluster
- SSH keys preferred over tokens for ArgoCD

### 4. Pre-flight Validation (internal/validation/)

**Purpose:** Validate prerequisites before bootstrap

**Validators:**
```go
type Validator interface {
    Name() string
    Validate(ctx context.Context) error
}

// Specific validators
type ClusterValidator struct{}      // Check kubeconfig and cluster access
type GitValidator struct{}          // Check Git credentials and repo access
type ToolValidator struct{}         // Check required tools installed
type DNSValidator struct{}          // Check DNS records (optional)
```

**Validation Flow:**
1. Check kubeconfig exists and is valid
2. Verify cluster is reachable
3. Validate Git provider credentials
4. Verify GitOps repository is accessible
5. Check required tools: kubectl, talosctl, argocd, git
6. Optionally validate DNS records

**Key Design Decisions:**
- Fail fast on validation errors
- Provide actionable error messages
- Run all validators, report all failures
- DNS validation is optional (not all setups need it)


### 5. Progress Tracking (internal/progress/)

**Purpose:** Display bootstrap progress to users

**Stepper Interface:**
```go
type Stepper interface {
    NewStep(name string) Step
    CompleteStep(step Step)
    FailStep(step Step, err error)
    DisplaySummary()
}

type Step struct {
    Name      string
    Status    Status // Pending, InProgress, Complete, Failed
    StartTime time.Time
    EndTime   time.Time
    Error     error
}
```

**Display Modes:**
- **Simple Mode:** Text-based progress (default)
- **Interactive Mode:** BubbleTea UI (optional, for k3d-like experience)

**Example Output:**
```
⏳ Validating prerequisites...
✅ Validating prerequisites
⏳ Setting up Git authentication...
✅ Setting up Git authentication
⏳ Installing ArgoCD...
✅ Installing ArgoCD
⏳ Deploying platform applications...
✅ Deploying platform applications
⏳ Waiting for sync...
✅ Waiting for sync

🎉 Platform bootstrap complete!

Access URLs:
  ArgoCD: https://argocd.example.com
  Console: https://console.example.com

Credentials stored in: ~/.platform/credentials.yaml
```

**Key Design Decisions:**
- Simple text mode by default (no BubbleTea dependency)
- Emoji indicators for visual feedback
- Time tracking for performance analysis
- Summary at end with access URLs

### 6. State Management (internal/state/)

**Purpose:** Track bootstrap progress and enable resumption

**State Structure:**
```go
type State struct {
    ClusterName    string
    Environment    string
    GitRepo        string
    StartTime      time.Time
    CompletedSteps []string
    Status         string // InProgress, Complete, Failed
    Metadata       map[string]string
}
```

**Storage Locations:**
1. **Local:** `~/.platform/state.yaml` (for CLI resumption)
2. **Cluster:** Secret `platform-initial-state` in `argocd` namespace (for disaster recovery)

**State Operations:**
- Load state from file
- Check if step is complete
- Mark step as complete
- Save state to file
- Backup state to cluster

**Key Design Decisions:**
- YAML format for human readability
- Local state for CLI operations
- Cluster backup for disaster recovery
- State includes metadata for debugging


### 7. Kubernetes Client Wrapper (internal/k8s/)

**Purpose:** Simplify Kubernetes operations and resource waiting

**Client Interface:**
```go
type Client struct {
    clientset *kubernetes.Clientset
    dynamic   dynamic.Interface
}

// Resource operations
func (c *Client) Apply(ctx context.Context, manifest string) error
func (c *Client) Get(ctx context.Context, gvk schema.GroupVersionKind, name, namespace string) (*unstructured.Unstructured, error)
func (c *Client) CreateSecret(ctx context.Context, secret *corev1.Secret) error

// Waiting operations
func (c *Client) WaitForPods(ctx context.Context, namespace, labelSelector string, timeout time.Duration) error
func (c *Client) WaitForCRD(ctx context.Context, crdName string, timeout time.Duration) error
func (c *Client) WaitForArgoApp(ctx context.Context, appName, namespace string, timeout time.Duration) error
```

**Key Design Decisions:**
- Wrap client-go for simpler API
- Provide waiting utilities for common operations
- Use context for cancellation and timeouts
- Support both typed and dynamic clients

### 8. Telemetry Tracker (internal/telemetry/)

**Purpose:** Track bootstrap success/failure for product improvement

**Tracker Interface:**
```go
type Tracker struct {
    enabled bool
    client  *http.Client
}

func (t *Tracker) TrackStepStart(step string)
func (t *Tracker) TrackStepComplete(step string, duration time.Duration)
func (t *Tracker) TrackStepFailed(step string, errorType string)
func (t *Tracker) TrackBootstrapComplete(duration time.Duration)
```

**Data Collected (Anonymized):**
- Step completion/failure events
- Duration of each step
- Error types (not error messages)
- Platform version
- No PII, no cluster details, no credentials

**Key Design Decisions:**
- Opt-out via flag or environment variable
- Anonymized data only
- Non-blocking (failures don't affect bootstrap)
- Simple HTTP POST to telemetry endpoint


## Data Models

### Bootstrap Configuration

```yaml
# ~/.platform/config.yaml
cluster:
  name: production
  kubeconfig: ~/.kube/config
  
git:
  provider: github  # or gitlab
  repo: https://github.com/org/infra-platform
  token: ghp_xxxxx  # or from env var
  
platform:
  environment: production
  domain: example.com
  
telemetry:
  enabled: true
```

### Bootstrap State

```yaml
# ~/.platform/state.yaml
clusterName: production
environment: production
gitRepo: https://github.com/org/infra-platform
startTime: "2025-11-23T10:00:00Z"
status: InProgress
completedSteps:
  - ValidatePrerequisites
  - SetupGitAuthentication
  - InstallArgoCD
metadata:
  cliVersion: v1.0.0
  kubernetesVersion: v1.28.0
```

### ArgoCD Application Manifest

```yaml
# Generated by CLI
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-foundation
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  project: default
  source:
    repoURL: https://github.com/org/infra-platform
    targetRevision: main
    path: platform/01-foundation
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

## Error Handling

### Error Wrapping Strategy

```go
// Wrap errors with context at each layer
func (o *Orchestrator) InstallArgoCD(ctx context.Context) error {
    if err := o.k8sClient.Apply(ctx, argocdManifest); err != nil {
        return fmt.Errorf("failed to apply ArgoCD manifests: %w", err)
    }
    
    if err := o.k8sClient.WaitForPods(ctx, "argocd", "app.kubernetes.io/name=argocd-server", 5*time.Minute); err != nil {
        return fmt.Errorf("ArgoCD pods did not become ready: %w", err)
    }
    
    return nil
}
```

### Error Types

1. **Validation Errors:** Pre-flight checks failed (user fixable)
2. **Network Errors:** Cluster or Git unreachable (transient)
3. **Permission Errors:** Insufficient RBAC or Git permissions (user fixable)
4. **Timeout Errors:** Resources didn't become ready (may be transient)
5. **Configuration Errors:** Invalid manifests or configuration (user fixable)

### Recovery Guidance

Each error type includes remediation hints:
- Validation: "Check kubeconfig is valid: kubectl cluster-info"
- Network: "Verify cluster is reachable, retry in a few minutes"
- Permission: "Ensure Git token has 'repo' and 'admin:repo_hook' scopes"
- Timeout: "Check pod logs: kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server"
- Configuration: "Validate manifest syntax: kubectl apply --dry-run=client -f manifest.yaml"


## Testing Strategy

### Unit Testing

**Approach:** Test individual components in isolation

**Coverage:**
- GitShim implementations (mock HTTP responses)
- Validators (mock Kubernetes client)
- State manager (filesystem operations)
- Progress stepper (output verification)

**Example:**
```go
func TestGitHubProvider_ValidateCredentials(t *testing.T) {
    server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.WriteHeader(http.StatusOK)
        json.NewEncoder(w).Encode(map[string]string{"login": "testuser"})
    }))
    defer server.Close()
    
    provider := &GitHubProvider{
        token:   "test-token",
        baseURL: server.URL,
    }
    
    err := provider.ValidateCredentials(context.Background())
    assert.NoError(t, err)
}
```

### Integration Testing

**Approach:** Test against real Kubernetes cluster (kind or k3d)

**Scenarios:**
1. Bootstrap fresh cluster
2. Resume after failure
3. Re-run on already bootstrapped cluster (idempotency)
4. Validate command without bootstrap
5. Status command on running platform

**Setup:**
```bash
# Create test cluster
kind create cluster --name platform-test

# Run integration tests
go test -tags=integration ./test/integration/...

# Cleanup
kind delete cluster --name platform-test
```

### End-to-End Testing

**Approach:** Full bootstrap on Talos cluster

**Manual Test Plan:**
1. Provision Talos cluster
2. Run `platform bootstrap --repo <url> --env test`
3. Verify ArgoCD is installed
4. Verify platform applications are synced
5. Verify Crossplane providers are healthy
6. Verify Gateway API Gateway exists
7. Create test WebService claim
8. Verify HTTPRoute is created
9. Run `platform status` and verify output
10. Run `platform destroy` and verify cleanup


## Implementation Phases

### Phase 1: Core CLI Structure
- Set up Go project with Cobra and Viper
- Implement root command and basic flags
- Create configuration loading
- Set up logging (console + file)

### Phase 2: Pre-flight Validation
- Implement validator interface
- Create cluster, Git, tool, and DNS validators
- Add validation command
- Test validation logic

### Phase 3: GitShim Abstraction
- Define GitShim interface
- Implement GitHub provider
- Implement GitLab provider
- Add SSH key generation
- Test with both providers

### Phase 4: Bootstrap Orchestration
- Implement orchestrator structure
- Create ArgoCD installation step
- Create secrets configuration step
- Create platform application deployment step
- Add waiting logic for resource readiness

### Phase 5: State Management
- Implement local state persistence
- Add step completion tracking
- Create cluster state backup
- Test resumption after failure

### Phase 6: Progress Display
- Implement simple text-based stepper
- Add emoji indicators
- Create summary display
- Optionally add BubbleTea UI

### Phase 7: Additional Commands
- Implement status command
- Implement destroy command
- Add telemetry tracking
- Create comprehensive help text

### Phase 8: Crossplane Integration
- Add Crossplane provider validation
- Add Gateway API validation
- Verify XRD and Composition sync
- Test with example claims

### Phase 9: Testing and Documentation
- Write unit tests
- Create integration tests
- Write user documentation
- Create developer documentation

### Phase 10: Release Preparation
- Set up CI/CD pipeline
- Create release artifacts
- Write changelog
- Publish documentation


## Security Considerations

### Credential Management

**Git Tokens:**
- Accept via flag, environment variable, or config file
- Never log tokens
- Store in Kubernetes Secrets (not in Git)
- Use least-privilege scopes (repo, admin:repo_hook)

**SSH Keys:**
- Generate ephemeral keys for ArgoCD
- Store private key in Kubernetes Secret
- Register public key with Git provider
- Rotate keys on re-bootstrap

**Kubeconfig:**
- Use existing kubeconfig from user
- Never modify or store kubeconfig
- Respect KUBECONFIG environment variable

### RBAC

**CLI Requirements:**
- Cluster-admin access (for ArgoCD installation)
- Namespace creation permissions
- Secret creation permissions

**ArgoCD Service Account:**
- Least-privilege RBAC for platform management
- Defined in ArgoCD installation manifests
- Scoped to platform namespaces

### Secret Storage

**Approach:** Bootstrap Secret + External Secrets Operator

**The "Key to the Factory" Pattern:**
- CLI creates ONE initial Kubernetes Secret: ArgoCD repository credential
- This is the "bootstrap secret" that allows ArgoCD to access the Git repository
- Once ArgoCD is running, External Secrets Operator syncs all other secrets from GitHub Secrets
- No secrets committed to Git

**Implementation:**
```yaml
# Created by CLI during bootstrap
apiVersion: v1
kind: Secret
metadata:
  name: platform-repo-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: https://github.com/org/infra-platform
  sshPrivateKey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----
```

**After Bootstrap:**
- External Secrets Operator syncs application secrets from GitHub Secrets
- Platform secrets managed via GitOps
- Bootstrap secret remains static (only rotated manually)

## Performance Considerations

### Bootstrap Time

**Target:** < 10 minutes for full bootstrap

**Breakdown:**
- Pre-flight validation: 30 seconds
- ArgoCD installation: 2 minutes
- Platform sync: 5 minutes
- Validation: 2 minutes

**Optimization:**
- Parallel validation checks
- Efficient waiting (polling with backoff)
- Minimal logging overhead

### Resource Usage

**CLI:**
- Memory: < 100MB
- CPU: Minimal (mostly waiting)
- Disk: < 10MB for logs and state

**Cluster Impact:**
- ArgoCD: ~500MB memory
- Platform components: Varies by layer
- No impact on existing workloads


## Monitoring and Observability

### Metrics

**What to Track:**
- Bootstrap success/failure rate
- Time per step
- Error types and frequency
- Platform component health

**Implementation:**
- Telemetry for aggregate metrics
- Local logs for debugging
- Cluster state for disaster recovery

### Logging

**Log Levels:**
- DEBUG: Detailed operation logs
- INFO: Step progress
- WARN: Non-fatal issues
- ERROR: Fatal errors

**Log Destinations:**
- Console: INFO and above (human-readable)
- File: DEBUG and above (structured JSON)

**Example Log Entry:**
```json
{
  "timestamp": "2025-11-23T10:05:30Z",
  "level": "info",
  "step": "InstallArgoCD",
  "message": "Waiting for ArgoCD pods to be ready",
  "namespace": "argocd",
  "timeout": "5m"
}
```

### Alerting

**Approach:** No built-in alerting (CLI is interactive)

**Post-Bootstrap:**
- Robusta monitors platform health
- Kagent receives alerts and proposes fixes
- CLI only used for Day 0 bootstrap

## Dependencies

### External Dependencies

**Required:**
- Go >= 1.21
- kubectl (for cluster operations)
- git (for repository operations)

**Optional:**
- talosctl (for Talos-specific operations)
- argocd CLI (for advanced ArgoCD operations)

### Go Dependencies

```go
// go.mod
module github.com/org/platform-cli

go 1.21

require (
    github.com/spf13/cobra v1.8.0
    github.com/spf13/viper v1.18.0
    github.com/rs/zerolog v1.31.0
    k8s.io/client-go v0.28.0
    k8s.io/api v0.28.0
    k8s.io/apimachinery v0.28.0
    sigs.k8s.io/yaml v1.4.0
)
```

### Platform Dependencies

**Assumes Existing:**
- Talos cluster (or k3d for local dev)
- **Git repository with platform manifests already populated** (not scaffolded by CLI)
- Git provider (GitHub or GitLab)

**Installs:**
- ArgoCD
- Platform components (via ArgoCD)

**Important:** Unlike Kubefirst, this CLI does NOT scaffold a new repository from a template. The user must have an existing Git repository with platform manifests (the `infra-platform` monorepo). The CLI only connects the cluster to the existing repository.


## Compatibility with Crossplane API Spec

### Integration Points

**1. Platform Application Deployment**
- CLI creates ArgoCD Application pointing to `platform/04-apis/`
- Respects directory structure: `definitions/`, `compositions/`, `examples/`, `providers/`
- Does not modify Crossplane manifests

**2. Provider Validation**
- CLI waits for provider-kubernetes pods to be ready
- Verifies ProviderConfig exists
- Checks RBAC is configured
- Respects sync wave "1" for providers

**3. Gateway API Validation**
- CLI verifies Gateway API CRDs are installed
- Checks `cilium-gateway` exists in `default` namespace
- Validates Gateway status before allowing HTTPRoute compositions
- Does not create or modify Gateway (managed by foundation layer)

**4. Composition Validation**
- CLI can optionally run `crossplane beta render` on examples
- Uses same validation as CI pipeline
- Reports composition errors during bootstrap
- Does not modify compositions

**5. State Coordination**
- CLI tracks ArgoCD Application sync status
- Waits for Crossplane resources to be ready
- Does not interfere with GitOps-driven updates
- Respects ArgoCD sync waves

### Non-Interference Guarantees

**What CLI Does NOT Do:**
- Modify Crossplane XRDs or Compositions
- Apply Crossplane resources directly
- Bypass ArgoCD for platform updates
- Change Gateway API configuration
- Interfere with Kagent operations

**What CLI DOES Do:**
- Bootstrap ArgoCD
- Create ArgoCD Applications
- Validate prerequisites
- Wait for platform sync
- Report status

## Open Questions

1. **BubbleTea Dependency:** Should we include BubbleTea for rich UI, or keep it simple with text output?
   - **Recommendation:** Start simple, add BubbleTea as optional feature later

2. **Telemetry Endpoint:** Where should telemetry data be sent?
   - **Recommendation:** Self-hosted endpoint or disable by default

3. **Multi-Cluster Support:** Should CLI support managing multiple clusters?
   - **Recommendation:** Single cluster for MVP, add multi-cluster later

4. **Talos-Specific Features:** Should CLI have Talos-specific commands (e.g., node management)?
   - **Recommendation:** No, keep CLI focused on bootstrap. Use talosctl for node operations

5. **Credential Rotation:** Should CLI support rotating Git credentials?
   - **Recommendation:** Manual rotation via `platform bootstrap --rotate-credentials` command

## Design Decisions vs Kubefirst

**What We Adopted from Kubefirst:**
- CLI structure (Cobra + Viper)
- Progress tracking (Stepper pattern)
- GitShim abstraction
- State management
- Idempotent operations
- Telemetry pattern

**What We Intentionally Omitted:**
- **Repository Scaffolding:** We assume the Git repository already exists with platform manifests. Kubefirst generates repos from templates; we don't.
- **Multi-Cloud Providers:** We focus on Talos-first. Kubefirst supports 9+ cloud providers.
- **BubbleTea UI (initially):** We start with simple text output. Kubefirst uses rich terminal UI.
- **Embedded API Server:** Kubefirst runs a local API server; we interact directly with Kubernetes.

**Rationale:** Our platform is YAML-first and GitOps-centric. The CLI is a thin bootstrap wrapper, not a full platform management tool.

## Success Criteria

The design is successful when:

1. ✅ CLI can bootstrap platform from scratch in < 10 minutes
2. ✅ Bootstrap is idempotent (safe to re-run)
3. ✅ Pre-flight validation catches common errors
4. ✅ Progress feedback is clear and actionable
5. ✅ State is persisted for resumption
6. ✅ GitShim works with both GitHub and GitLab
7. ✅ Compatible with Crossplane API spec
8. ✅ Respects GitOps-first architecture
9. ✅ Logs are structured and useful for debugging
10. ✅ Error messages include remediation guidance
