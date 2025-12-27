# Release Pipeline Scripts

This directory contains the centralized release pipeline scripts that enable tenant services to deploy container artifacts across multiple environments through platform-managed CI/CD workflows.

## Overview

The release pipeline system provides:

- **Centralized CI/CD Logic**: Platform owns all pipeline execution, tenants provide configuration
- **GitOps Compliance**: All deployments happen through Git commits, never direct cluster access
- **Multi-Environment Support**: Automated dev deployment with manual promotion gates for staging/production
- **Consistent Infrastructure**: Both PR and main branch workflows use identical testing infrastructure (GitHub runners + Kind)
- **Immutable Artifacts**: SHA-tagged container images deployed across all environments

## Architecture

### Script Organization

```
scripts/release/
├── ci-pipeline.sh              # Main CI orchestration (entry point)
├── build-and-test.sh          # Build and test execution helper
├── create-artifact.sh         # Immutable artifact creation (main branch only)
├── release-pipeline.sh        # GitOps deployment orchestration
├── test-config-discovery.sh   # Configuration discovery validation
├── lib/                       # Shared libraries
│   ├── common.sh              # Common utilities and logging
│   ├── config-discovery.sh    # Tenant configuration discovery
│   └── logging.sh             # Enhanced logging and monitoring
└── README.md                  # This file
```

### Execution Flow

#### PR Workflow
```
GitHub Actions (PR) → ci-pipeline.sh → build-and-test.sh → Feedback Only
```

#### Main Branch Workflow
```
GitHub Actions (main) → ci-pipeline.sh → build-and-test.sh → create-artifact.sh → release-pipeline.sh → Auto Deploy to Dev
```

#### Manual Promotion
```
Manual Trigger → release-pipeline.sh → Promotion Gate → GitOps Update → ArgoCD Sync
```

## Usage

### From GitHub Actions

**Tenant CI Workflow** (`.github/workflows/ci.yml`):
```yaml
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - name: Run Platform CI Pipeline
      run: |
        ./zerotouch-platform/scripts/release/ci-pipeline.sh \
          --tenant=deepagents-runtime \
          --trigger=${{ github.event_name == 'pull_request' && 'pr' || 'main' }}
      env:
        BOT_GITHUB_TOKEN: ${{ secrets.BOT_GITHUB_TOKEN }}
        AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
        AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        AWS_SESSION_TOKEN: ${{ secrets.AWS_SESSION_TOKEN }}
```

### Manual Execution

**CI Pipeline**:
```bash
# PR workflow
./ci-pipeline.sh --tenant=deepagents-runtime --trigger=pr

# Main branch workflow
./ci-pipeline.sh --tenant=deepagents-runtime --trigger=main --verbose
```

**Release Pipeline**:
```bash
# Deploy to dev (automatic after main branch)
./release-pipeline.sh --tenant=deepagents-runtime --environment=dev

# Deploy to staging (requires manual promotion gate)
./release-pipeline.sh --tenant=deepagents-runtime --environment=staging --artifact=ghcr.io/org/deepagents-runtime:main-abc123
```

**Configuration Testing**:
```bash
# Test configuration discovery
./test-config-discovery.sh
```

## Configuration

### Tenant Configuration

Tenants configure the release pipeline through two files:

**`ci/config.yaml`** (Extended):
```yaml
service:
  name: "deepagents-runtime"
  namespace: "intelligence-deepagents"

build:
  dockerfile: "Dockerfile"
  context: "."
  tag: "ci-test"

# Release pipeline integration
release:
  enabled: true
  config_file: "ci/release.yaml"

# ... existing CI configuration
```

**`ci/release.yaml`** (New):
```yaml
release:
  environments: [dev, staging, production]
  promotion:
    dev_to_staging: manual
    staging_to_production: manual
  artifacts:
    registry: ghcr.io
    retention_days: 30
  testing:
    validation_mode: preview
    bootstrap_mode: preview

# ... detailed environment and deployment settings
```

### Environment Variables

**Required for CI Pipeline**:
- `BOT_GITHUB_TOKEN` - GitHub token for repository access
- `AWS_ACCESS_KEY_ID` - AWS credentials for configuration discovery
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN` (for OIDC authentication)

**Set by Pipeline**:
- `BUILD_TEST_IMAGE` - Built image name
- `BUILD_TEST_TAG` - Built image tag
- `ARTIFACT_ID` - Created artifact identifier
- `ARTIFACT_SHA` - Git commit SHA
- `DEPLOYMENT_COMMIT_SHA` - GitOps commit SHA

## Key Features

### 1. Configuration Discovery

The system automatically discovers tenant configuration from:
- Tenant repository (`ci/config.yaml`, `ci/release.yaml`)
- Zerotouch-tenants repository (environment definitions)
- Platform defaults and validation rules

### 2. Modular Architecture

Main scripts call helper scripts for specific tasks:
- **ci-pipeline.sh**: Orchestrates overall CI flow
- **build-and-test.sh**: Handles build and testing with Kind clusters
- **create-artifact.sh**: Creates immutable SHA-tagged artifacts
- **release-pipeline.sh**: Manages GitOps-based deployments

### 3. GitOps Compliance

All deployments happen through Git commits:
- Updates tenant repository with new image tags
- ArgoCD automatically syncs changes to clusters
- No direct cluster manipulation by pipeline scripts
- Full audit trail through Git history

### 4. Error Handling and Logging

Comprehensive error handling with:
- Detailed logging to files and console
- Step-by-step execution tracking
- Environment validation and prerequisites checking
- Retry logic with exponential backoff
- Clear error messages and troubleshooting guidance

### 5. Multi-Tenant Support

Tenant isolation through:
- Separate configuration discovery per tenant
- Isolated execution environments
- Tenant-specific credentials and permissions
- No cross-tenant resource conflicts

## Testing and Validation

### Configuration Discovery Test

```bash
./test-config-discovery.sh
```

Validates:
- Tenant configuration parsing
- Required field validation
- Environment name validation
- Tenant name format validation

### Integration Testing

The scripts integrate with existing platform testing infrastructure:
- Uses `scripts/bootstrap/preview/` for Kind cluster setup
- Leverages `scripts/bootstrap/validation/` for post-deployment validation
- Integrates with tenant-specific test scripts

## Troubleshooting

### Common Issues

1. **Configuration Discovery Fails**
   - Check tenant repository has `ci/config.yaml` and `ci/release.yaml`
   - Verify AWS credentials for zerotouch-tenants access
   - Validate configuration file syntax

2. **Build and Test Fails**
   - Check Docker is available and running
   - Verify Dockerfile path and build context
   - Check Kind cluster setup and image loading

3. **Artifact Creation Fails**
   - Verify GitHub token has registry push permissions
   - Check registry authentication
   - Validate image tagging and push operations

4. **Release Pipeline Fails**
   - Check GitHub token has tenant repository write access
   - Verify Git configuration and commit permissions
   - Validate manifest file locations and format

### Log Files

Logs are stored in `~/.cache/zerotouch-platform/logs/`:
- `{tenant}-{operation}-{timestamp}.log`
- Detailed execution logs with timestamps
- Error context and troubleshooting information

### Debug Mode

Enable verbose logging:
```bash
./ci-pipeline.sh --tenant=deepagents-runtime --trigger=pr --verbose
```

Or set environment variable:
```bash
export LOG_LEVEL=debug
./ci-pipeline.sh --tenant=deepagents-runtime --trigger=pr
```

## Integration Points

### Platform Integration

- **Bootstrap Scripts**: Uses existing preview mode setup
- **Validation Scripts**: Integrates with platform validation framework
- **Crossplane XRDs**: Consumes release pipeline infrastructure resources
- **External Secrets**: Accesses credentials from AWS SSM Parameter Store

### Tenant Integration

- **GitHub Actions**: Tenant workflows call platform scripts
- **Configuration Files**: Tenants provide CI and release configuration
- **Manifest Updates**: GitOps updates to tenant repository overlays
- **ArgoCD Applications**: Automatic sync of deployment changes

## Future Enhancements

- **Promotion Gate UI**: Web interface for manual approvals
- **Deployment Monitoring**: Real-time deployment status tracking
- **Rollback Automation**: Automatic rollback on health check failures
- **Multi-Registry Support**: Support for additional container registries
- **Advanced Testing**: Integration with more sophisticated testing frameworks