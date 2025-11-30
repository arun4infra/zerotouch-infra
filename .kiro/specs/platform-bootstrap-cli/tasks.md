# Implementation Plan

- [ ] 1. Set up Go project structure and dependencies
  - Initialize Go module with `go mod init`
  - Add Cobra, Viper, client-go, zerolog dependencies
  - Create directory structure: `cmd/`, `internal/`, `main.go`
  - Set up `.gitignore` for Go projects
  - _Requirements: 1.1, 1.3_

- [ ] 2. Implement root command and configuration
  - [ ] 2.1 Create root command with Cobra
    - Define root command structure
    - Add global flags: `--kubeconfig`, `--log-level`
    - Set up Viper integration for config and env vars
    - _Requirements: 1.1, 1.4_
  
  - [ ] 2.2 Implement configuration loading
    - Load config from `~/.platform/config.yaml`
    - Support environment variables with `PLATFORM_` prefix
    - Merge config sources (file, env, flags)
    - _Requirements: 1.4, 9.1_
  
  - [ ] 2.3 Set up structured logging
    - Configure zerolog for console and file output
    - Create `~/.platform/logs/` directory
    - Implement log file naming: `bootstrap-<timestamp>.log`
    - _Requirements: 6.1, 6.2, 6.3_

- [ ] 3. Implement validation command and pre-flight checks
  - [ ] 3.1 Create validate command
    - Define command structure and flags
    - Wire up to validation logic
    - _Requirements: 11.1, 11.2_
  
  - [ ] 3.2 Implement validator interface
    - Define Validator interface with Name() and Validate() methods
    - Create validator registry
    - _Requirements: 2.1_
  
  - [ ] 3.3 Implement cluster validator
    - Check kubeconfig exists and is valid
    - Verify cluster is reachable
    - Test Kubernetes API connectivity
    - _Requirements: 2.1_
  
  - [ ] 3.4 Implement Git validator
    - Validate Git provider credentials (token)
    - Check repository URL is accessible
    - Verify required permissions
    - _Requirements: 2.2_
  
  - [ ] 3.5 Implement tool validator
    - Check kubectl is installed and in PATH
    - Check git is installed
    - Optionally check talosctl and argocd CLI
    - _Requirements: 2.3_
  
  - [ ] 3.6 Wire up all validators
    - Run all validators and collect results
    - Display validation summary
    - Exit with appropriate status code
    - _Requirements: 2.5, 11.5_


- [ ] 4. Implement GitShim abstraction
  - [ ] 4.1 Define GitShim interface
    - Create Provider interface with methods: ValidateCredentials, CreateDeployToken, GenerateSSHKey, GetRepository
    - Define data structures: DeployToken, SSHKey, Repository
    - _Requirements: 16.1_
  
  - [ ] 4.2 Implement GitHub provider
    - Implement ValidateCredentials using GitHub API
    - Implement CreateDeployToken (deploy keys)
    - Implement GenerateSSHKey and register with GitHub
    - _Requirements: 16.2, 16.4_
  
  - [ ] 4.3 Implement GitLab provider
    - Implement ValidateCredentials using GitLab API
    - Implement CreateDeployToken (deploy tokens)
    - Implement GenerateSSHKey and register with GitLab
    - _Requirements: 16.2, 16.4_
  
  - [ ] 4.4 Implement SSH key generation
    - Generate RSA or Ed25519 SSH key pair
    - Format keys for storage
    - _Requirements: 3.3, 16.4_
  
  - [ ] 4.5 Implement provider factory
    - Detect provider from repository URL
    - Return appropriate provider implementation
    - _Requirements: 16.3_

- [ ] 5. Implement Kubernetes client wrapper
  - [ ] 5.1 Create Kubernetes client wrapper
    - Initialize clientset from kubeconfig
    - Initialize dynamic client
    - Add error handling
    - _Requirements: 2.1_
  
  - [ ] 5.2 Implement resource operations
    - Implement Apply method for manifests
    - Implement Get method for resources
    - Implement CreateSecret method
    - _Requirements: 3.2, 3.4_
  
  - [ ] 5.3 Implement waiting utilities
    - Implement WaitForPods with timeout
    - Implement WaitForCRD with timeout
    - Implement WaitForArgoApp with timeout
    - Use polling with exponential backoff
    - _Requirements: 3.2, 7.1_

- [ ] 6. Implement state management
  - [ ] 6.1 Create state manager
    - Define State struct with cluster info and completed steps
    - Implement Load and Save methods for `~/.platform/state.yaml`
    - _Requirements: 9.2, 9.3_
  
  - [ ] 6.2 Implement step tracking
    - Add methods: IsStepComplete, MarkStepComplete
    - Update state file after each step
    - _Requirements: 4.2, 9.4_
  
  - [ ] 6.3 Implement cluster state backup
    - Export state as Kubernetes Secret
    - Create Secret `platform-initial-state` in `argocd` namespace
    - Include metadata for disaster recovery
    - _Requirements: 9.5_


- [ ] 7. Implement progress tracking
  - [ ] 7.1 Create stepper interface
    - Define Stepper interface with NewStep, CompleteStep, FailStep methods
    - Define Step struct with name, status, timestamps
    - _Requirements: 5.1_
  
  - [ ] 7.2 Implement simple text stepper
    - Display steps with emoji indicators (⏳, ✅, ❌)
    - Show step name and status
    - Track timing for each step
    - _Requirements: 5.2, 5.3_
  
  - [ ] 7.3 Implement summary display
    - Show all completed steps
    - Display total time
    - Show access URLs and credentials location
    - _Requirements: 5.5_

- [ ] 8. Implement bootstrap orchestrator
  - [ ] 8.1 Create orchestrator structure
    - Define Orchestrator struct with dependencies (gitShim, k8sClient, stepper, stateManager)
    - Initialize all components
    - _Requirements: 3.1_
  
  - [ ] 8.2 Implement step execution framework
    - Create executeStep method that wraps step functions
    - Add error handling and state tracking
    - Skip completed steps (idempotency)
    - _Requirements: 4.1, 4.3_
  
  - [ ] 8.3 Implement ValidatePrerequisites step
    - Run all validators
    - Fail fast if validation fails
    - _Requirements: 2.1, 2.2, 2.3_
  
  - [ ] 8.4 Implement SetupGitAuthentication step
    - Generate SSH key using GitShim
    - Register key with Git provider
    - Store private key for next step
    - _Requirements: 3.3_
  
  - [ ] 8.5 Implement InstallArgoCD step
    - Apply ArgoCD installation manifests
    - Wait for ArgoCD pods to be ready
    - Verify ArgoCD API is accessible
    - _Requirements: 3.2_
  
  - [ ] 8.6 Implement ConfigureSecrets step
    - Create ArgoCD repository credential Secret with SSH key
    - Create any additional required secrets
    - _Requirements: 3.4_
  
  - [ ] 8.7 Implement DeployPlatformApps step
    - Create ArgoCD Applications for platform layers
    - Apply Applications in order: foundation, observability, intelligence, apis
    - _Requirements: 3.5_
  
  - [ ] 8.8 Implement WaitForSync step
    - Wait for all ArgoCD Applications to sync
    - Check sync status and health
    - Respect sync waves
    - _Requirements: 3.6, 15.4_
  
  - [ ] 8.9 Implement ValidateComponents step
    - Verify Crossplane providers are healthy
    - Verify Gateway API Gateway exists
    - Check critical platform components
    - _Requirements: 7.1, 7.2, 8.1, 8.2_
  
  - [ ] 8.10 Implement BackupState step
    - Export state to cluster Secret
    - Mark bootstrap as complete
    - _Requirements: 9.5_


- [ ] 9. Implement bootstrap command
  - [ ] 9.1 Create bootstrap command
    - Define command structure with flags: --repo, --env, --cluster-name, --git-provider, --git-token, --validate-only, --no-telemetry
    - Add help text and examples
    - _Requirements: 1.2, 1.3_
  
  - [ ] 9.2 Wire up orchestrator
    - Initialize orchestrator with all dependencies
    - Call orchestrator.Bootstrap()
    - Handle errors and display messages
    - _Requirements: 3.1_
  
  - [ ] 9.3 Implement idempotency checks
    - Check if ArgoCD is already installed
    - Check if platform Applications exist
    - Resume from last incomplete step
    - _Requirements: 4.1, 4.2, 4.3_
  
  - [ ] 9.4 Add validation-only mode
    - Support --validate-only flag
    - Run pre-flight checks without executing bootstrap
    - _Requirements: 11.1, 11.2_

- [ ] 10. Implement status command
  - [ ] 10.1 Create status command
    - Define command structure
    - Add help text
    - _Requirements: 12.1_
  
  - [ ] 10.2 Implement ArgoCD Application status check
    - Query all platform ArgoCD Applications
    - Display sync status and health
    - _Requirements: 12.1_
  
  - [ ] 10.3 Implement component health check
    - Check pod status for critical components
    - Display color-coded status (green, yellow, red)
    - _Requirements: 12.2, 12.3_
  
  - [ ] 10.4 Display summary
    - Show overall platform health
    - Display access URLs
    - Highlight any issues
    - _Requirements: 12.4, 12.5_

- [ ] 11. Implement destroy command
  - [ ] 11.1 Create destroy command
    - Define command structure
    - Add confirmation prompt
    - _Requirements: 13.1_
  
  - [ ] 11.2 Implement platform teardown
    - Delete ArgoCD Applications in reverse order
    - Delete ArgoCD installation
    - _Requirements: 13.2, 13.3_
  
  - [ ] 11.3 Clean up local state
    - Remove `~/.platform/state.yaml`
    - Display completion message
    - _Requirements: 13.4, 13.5_


- [ ] 12. Implement telemetry tracking
  - [ ]* 12.1 Create telemetry tracker
    - Define Tracker struct with enabled flag and HTTP client
    - Implement methods: TrackStepStart, TrackStepComplete, TrackStepFailed, TrackBootstrapComplete
    - _Requirements: 17.1_
  
  - [ ]* 12.2 Implement anonymized data collection
    - Collect step completion/failure events
    - Track duration of each step
    - Track error types (not messages)
    - No PII, no cluster details
    - _Requirements: 17.2_
  
  - [ ]* 12.3 Implement opt-out mechanism
    - Respect --no-telemetry flag
    - Respect PLATFORM_TELEMETRY=false env var
    - Make telemetry non-blocking
    - _Requirements: 17.3, 17.5_
  
  - [ ]* 12.4 Wire up telemetry to orchestrator
    - Track each step start/complete/fail
    - Track overall bootstrap completion
    - _Requirements: 17.4_

- [ ] 13. Implement Crossplane validation
  - [ ] 13.1 Add Crossplane provider health check
    - Wait for provider-kubernetes pods to be ready
    - Verify ProviderConfig exists
    - _Requirements: 7.1, 7.2, 14.2_
  
  - [ ] 13.2 Add Gateway API validation
    - Verify Gateway API CRDs are installed
    - Check cilium-gateway exists in default namespace
    - Verify Gateway status is Programmed
    - _Requirements: 8.1, 8.2, 8.3, 14.3_
  
  - [ ]* 13.3 Add composition validation (optional)
    - Optionally run crossplane beta render on examples
    - Report composition errors
    - _Requirements: 14.4_

- [ ] 14. Add error handling and recovery guidance
  - [ ] 14.1 Implement error wrapping
    - Wrap errors with context at each layer
    - Use fmt.Errorf with %w
    - _Requirements: 10.1_
  
  - [ ] 14.2 Add remediation hints
    - Map error types to remediation messages
    - Display actionable guidance
    - _Requirements: 10.2_
  
  - [ ] 14.3 Implement graceful failure
    - Clean up partial state on errors
    - Log full error details to file
    - _Requirements: 10.3, 10.5_


- [ ] 15. Create ArgoCD manifests and Application templates
  - [ ] 15.1 Create ArgoCD installation manifest
    - Use official ArgoCD installation YAML
    - Configure for platform use case
    - _Requirements: 3.2_
  
  - [ ] 15.2 Create ArgoCD Application templates
    - Create templates for foundation, observability, intelligence, apis layers
    - Set appropriate sync waves
    - Configure automated sync policies
    - _Requirements: 3.5, 3.6, 14.2_
  
  - [ ] 15.3 Create repository credential Secret template
    - Template for ArgoCD Git credentials
    - Support SSH key authentication
    - _Requirements: 3.4_

- [ ] 16. Write unit tests
  - [ ]* 16.1 Test GitShim implementations
    - Mock HTTP responses for GitHub and GitLab APIs
    - Test credential validation
    - Test SSH key generation
    - _Requirements: 16.1, 16.2, 16.4_
  
  - [ ]* 16.2 Test validators
    - Mock Kubernetes client
    - Test cluster, Git, and tool validators
    - _Requirements: 2.1, 2.2, 2.3_
  
  - [ ]* 16.3 Test state manager
    - Test Load and Save operations
    - Test step tracking
    - _Requirements: 9.2, 9.3_
  
  - [ ]* 16.4 Test progress stepper
    - Verify output formatting
    - Test step status transitions
    - _Requirements: 5.1, 5.2_

- [ ] 17. Write integration tests
  - [ ] 17.1 Set up test cluster
    - Create kind or k3d cluster for testing
    - Document setup process
    - _Requirements: 3.1_
  
  - [ ] 17.2 Test bootstrap on fresh cluster
    - Run full bootstrap
    - Verify all components are installed
    - _Requirements: 3.1, 3.2, 3.5_
  
  - [ ] 17.3 Test idempotency
    - Re-run bootstrap on already bootstrapped cluster
    - Verify no errors and same end state
    - _Requirements: 4.1, 4.4_
  
  - [ ] 17.4 Test resumption after failure
    - Simulate failure mid-bootstrap
    - Re-run and verify resumption from last step
    - _Requirements: 4.3_


- [ ] 18. Create documentation
  - [ ] 18.1 Write user documentation
    - Create README with installation instructions
    - Document all commands and flags
    - Add usage examples
    - _Requirements: 1.3_
  
  - [ ]* 18.2 Write developer documentation
    - Document architecture and design decisions
    - Add contribution guidelines
    - Document testing procedures
    - _Requirements: 14.5_
  
  - [ ]* 18.3 Create troubleshooting guide
    - Document common errors and solutions
    - Add debugging tips
    - _Requirements: 10.2_
  
  - [ ]* 18.4 Document compatibility with Crossplane spec
    - Explain how CLI works with platform APIs
    - Document validation steps
    - _Requirements: 14.1, 14.5_

- [ ] 19. Set up CI/CD pipeline
  - [ ] 19.1 Create GitHub Actions workflow
    - Add linting (golangci-lint)
    - Add unit tests
    - Add integration tests
    - _Requirements: 3.1_
  
  - [ ] 19.2 Set up release automation
    - Create release workflow
    - Build binaries for multiple platforms (Linux, macOS, Windows)
    - Create GitHub releases
    - _Requirements: 1.5_
  
  - [ ] 19.3 Add version management
    - Implement version command
    - Embed version at build time
    - _Requirements: 1.5_

- [ ] 20. Final integration and testing
  - [ ] 20.1 Test on Talos cluster
    - Provision Talos cluster
    - Run full bootstrap
    - Verify all platform components
    - _Requirements: 3.1, 14.1_
  
  - [ ] 20.2 Test Crossplane integration
    - Verify providers are healthy
    - Verify Gateway API is configured
    - Create test WebService claim
    - Verify HTTPRoute is created
    - _Requirements: 7.1, 8.1, 14.2, 14.3_
  
  - [ ] 20.3 Test status and destroy commands
    - Run platform status and verify output
    - Run platform destroy and verify cleanup
    - _Requirements: 12.1, 13.1_
  
  - [ ] 20.4 Verify GitOps-first architecture
    - Confirm CLI doesn't apply platform manifests directly
    - Verify ArgoCD manages all platform resources
    - _Requirements: 15.1, 15.2, 15.5_

- [ ] 21. Release preparation
  - [ ] 21.1 Create changelog
    - Document all features
    - List known limitations
    - _Requirements: 1.1_
  
  - [ ] 21.2 Publish documentation
    - Host documentation (GitHub Pages or similar)
    - Create quickstart guide
    - _Requirements: 1.3_
  
  - [ ] 21.3 Create release artifacts
    - Build binaries for all platforms
    - Create installation scripts
    - Publish to GitHub releases
    - _Requirements: 1.5_
