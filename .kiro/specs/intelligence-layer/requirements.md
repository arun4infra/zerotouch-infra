# Requirements Document: Intelligence Layer - Documentation Automation

## Introduction

This document defines requirements for the Documentation Automation System within the Intelligence Layer. The system uses Kagent to automatically maintain structured documentation in `artifacts/` following strict standards, while allowing humans to write free-form content in `docs/`.

**Scope:** Documentation automation, agent-maintained knowledge base, Qdrant indexing, CI auto-fix, and human/agent content separation.

## Glossary

- **Twin Docs**: Specification files in `artifacts/specs/` that mirror platform resources 1:1
- **Artifacts Zone**: Agent-maintained directory (`artifacts/`) with strict format and validation
- **Docs Zone**: Human-writable directory (`docs/`) with no format restrictions
- **Librarian Agent**: Kagent agent responsible for maintaining `artifacts/` following ADR 003 standards
- **No-Fluff Policy**: Documentation rule requiring tables/lists only, no prose paragraphs
- **Distillation**: Process where agent extracts useful information from `docs/` and creates structured content in `artifacts/`
- **docs-mcp Server**: MCP tool server providing documentation operations to the Librarian Agent

## Requirements

### Requirement 1: Separation of Human and Agent Content

**User Story:** As a developer, I want to write free-form documentation in `docs/` without worrying about agent format rules, so that I can document ideas quickly.

**Reference Pattern:** ✅ Two-zone architecture (human vs. agent ownership)

#### Acceptance Criteria

1. WHEN humans write content, THE Content SHALL be placed in `docs/` with no format restrictions
2. WHEN agent creates content, THE Content SHALL be placed in `artifacts/` following ADR 003 standards
3. WHEN validation runs, THE Validation SHALL check only `artifacts/` (skip `docs/`)
4. WHERE Qdrant indexing occurs, THE Indexing SHALL index only `artifacts/` (skip `docs/`)
5. WHEN CODEOWNERS is configured, THE Configuration SHALL restrict direct commits to `artifacts/` to agent only

### Requirement 2: Agent Content Distillation

**User Story:** As a platform operator, I want the agent to extract useful operational knowledge from developer notes and convert it to structured format, so that it becomes searchable and actionable.

**Reference Pattern:** ⚠️ CUSTOM - Agent reads `docs/` PRs, creates `artifacts/` content

#### Acceptance Criteria

1. WHEN a PR adds/modifies files in `docs/`, THE Librarian Agent SHALL read the content
2. WHEN agent reads human docs, THE Agent SHALL identify operationally useful information
3. WHEN useful info is found, THE Agent SHALL create/update corresponding file in `artifacts/` using strict templates
4. WHERE duplicate information exists, THE Agent SHALL update existing `artifacts/` file (not create duplicate)
5. WHEN distilling content, THE Agent SHALL preserve original `docs/` file unchanged

### Requirement 3: Twin Docs for Platform Resources

**User Story:** As a platform user, I want up-to-date specifications for each platform API, so that I know what parameters are available and how to use them.

**Reference Pattern:** ✅ 1:1 mapping between `platform/` resources and `artifacts/specs/`

#### Acceptance Criteria

1. WHEN a new Composition is added to `platform/04-apis/compositions/`, THE Agent SHALL create corresponding spec in `artifacts/specs/`
2. WHEN an existing Composition is modified, THE Agent SHALL update Configuration Parameters table in existing spec
3. WHEN creating specs, THE Agent SHALL use `artifacts/templates/spec-template.md`
4. WHERE parameters change, THE Agent SHALL update only the affected table rows (preserve other sections)
5. WHEN spec is created/updated, THE Agent SHALL commit to same PR branch

### Requirement 4: Strict Format Enforcement for Artifacts

**User Story:** As an AI agent, I want all documentation in `artifacts/` to follow a strict schema, so that I can reliably parse and search documentation.

**Reference Pattern:** ✅ ADR 003 standards (No-Fluff policy, templates, naming conventions)

#### Acceptance Criteria

1. WHEN creating documentation in `artifacts/`, THE Agent SHALL use ONLY templates from `artifacts/templates/`
2. WHEN writing content, THE Agent SHALL use ONLY tables, bullet lists, or code blocks (no prose paragraphs)
3. WHEN naming files, THE Agent SHALL use kebab-case, max 3 words, no timestamps/versions
4. WHERE frontmatter is required, THE Agent SHALL fill all required fields matching category schema
5. WHEN validation runs, THE CI SHALL reject PRs with violations in `artifacts/`

### Requirement 5: CI Validation and Auto-Fix

**User Story:** As a platform maintainer, I want documentation violations to be fixed automatically by the agent, so that PRs are not blocked by formatting issues.

**Reference Pattern:** ✅ Kagent invocation on CI failure

#### Acceptance Criteria

1. WHEN CI detects validation errors in `artifacts/`, THE Workflow SHALL invoke Librarian Agent
2. WHEN agent is invoked, THE Agent SHALL read validation error messages from CI logs
3. WHEN fixing violations, THE Agent SHALL fetch offending files, correct issues, validate fix
4. WHERE fixes are applied, THE Agent SHALL commit fixes to same PR branch
5. WHEN agent commits, THE CI SHALL re-run automatically (auto-fix loop until pass)

### Requirement 6: Qdrant Vector Database Integration

**User Story:** As the Librarian Agent, I want to search for similar documentation semantically, so that I can determine whether to create new files or update existing ones.

**Reference Pattern:** ✅ ADR 002 (Qdrant as index, Git as source of truth)

#### Acceptance Criteria

1. WHEN Qdrant is deployed, THE Deployment SHALL be a StatefulSet in `platform/03-intelligence/`
2. WHEN indexing documentation, THE Ingestion SHALL index ONLY `artifacts/` directory
3. WHEN storing in Qdrant, THE Storage SHALL include metadata only (file path, title, category, commit hash, embeddings)
4. WHERE content is needed, THE Agent SHALL fetch from Git using file path from Qdrant results
5. WHEN indexing runs, THE Indexing SHALL trigger on merge to `main` only (not on PRs)

### Requirement 7: MCP Tool Server for Documentation Operations

**User Story:** As the Librarian Agent, I want standardized tools for documentation operations, so that I can validate, create, update, and search documentation reliably.

**Reference Pattern:** ✅ kyverno-mcp pattern (MCP server + Kagent integration)

#### Acceptance Criteria

1. WHEN deploying docs-mcp server, THE Deployment SHALL include ServiceAccount, Deployment, Service, KEDA ScaledObject
2. WHEN exposing tools, THE MCP Server SHALL provide: `validate_doc`, `create_doc`, `update_doc`, `search_qdrant`, `fetch_from_git`, `commit_to_pr`, `sync_to_qdrant`
3. WHEN KEDA is configured, THE Configuration SHALL scale docs-mcp from 0 to 5 replicas based on request load
4. WHERE GitHub API is needed, THE Server SHALL use GitHub bot token with repo write permissions
5. WHEN validation runs, THE MCP Tools SHALL call existing Python scripts (no duplicate logic)

### Requirement 8: Librarian Agent Configuration

**User Story:** As a platform architect, I want the Librarian Agent to have clear instructions embedded in its system prompt, so that it knows the rules before creating documentation.

**Reference Pattern:** ✅ kyverno-agent.yaml pattern (Kagent Agent CRD with systemMessage)

#### Acceptance Criteria

1. WHEN deploying agent, THE Agent SHALL be a Kagent `Agent` CRD in `platform/03-intelligence/`
2. WHEN configuring system prompt, THE Prompt SHALL embed ADR 003 standards (No-Fluff policy, templates, naming, decision logic)
3. WHEN defining tools, THE Agent SHALL reference docs-mcp server tools by name
4. WHERE decision logic is needed, THE Prompt SHALL include deterministic rules for create vs. update
5. WHEN invoked, THE Agent SHALL validate before committing (never commit invalid docs)

### Requirement 9: GitHub Integration and CODEOWNERS

**User Story:** As a platform operator, I want to prevent accidental human commits to `artifacts/`, so that only the agent can modify agent-maintained content.

**Reference Pattern:** ✅ GitHub CODEOWNERS pattern

#### Acceptance Criteria

1. WHEN CODEOWNERS is configured, THE File SHALL restrict `/artifacts/` to agent bot account
2. WHEN humans create PRs, THE PRs SHALL be blocked if they modify `artifacts/` directly
3. WHEN agent commits, THE Commits SHALL use GitHub App token (bypasses CODEOWNERS)
4. WHERE CI validation runs, THE Validation SHALL check commit author (human → reject, agent → allow)
5. WHEN agent is invoked, THE Agent SHALL have write access to all branches via GitHub API

### Requirement 10: Decision Logic for Create vs. Update

**User Story:** As the Librarian Agent, I want clear rules for when to create new files vs. update existing files, so that I don't pollute `artifacts/` with duplicates.

**Reference Pattern:** ✅ ADR 003 decision tree

#### Acceptance Criteria

1. WHEN handling Twin Docs, THE Agent SHALL create only if file doesn't exist (1 spec per platform resource)
2. WHEN handling runbooks, THE Agent SHALL search Qdrant for similar docs using semantic search
3. WHEN similarity score > 0.85, THE Agent SHALL update existing runbook (append to Related Incidents table)
4. WHERE similarity score < 0.85, THE Agent SHALL create new runbook from template
5. WHEN handling ADRs, THE Agent SHALL always create new (auto-increment number)

### Requirement 11: Template Management

**User Story:** As a platform developer, I want templates to be version-controlled and agent-accessible, so that documentation structure remains consistent.

**Reference Pattern:** ✅ Template pattern from ADR 003

#### Acceptance Criteria

1. WHEN templates are stored, THE Templates SHALL be in `artifacts/templates/` (agent-accessible)
2. WHEN template types exist, THE Types SHALL include: `runbook-template.md`, `spec-template.md`, `adr-template.md`
3. WHEN agent creates docs, THE Agent SHALL copy template and fill placeholders
4. WHERE frontmatter is required, THE Template SHALL define required fields for category
5. WHEN templates change, THE Changes SHALL be version-controlled and deployed via ArgoCD

### Requirement 12: Distillation Workflow Example

**User Story:** As a developer, I want to document troubleshooting steps in my own format, and have the agent convert it to structured format automatically.

**Reference Pattern:** ⚠️ CUSTOM - Agent distillation logic

#### Acceptance Criteria

1. WHEN human writes `docs/troubleshooting/postgres-notes.md` (free-form), THE Content SHALL be allowed without validation
2. WHEN PR is created, THE Librarian Agent SHALL read `docs/troubleshooting/postgres-notes.md`
3. WHEN agent identifies operational steps, THE Agent SHALL extract symptoms, diagnosis, solution
4. WHERE structured runbook is needed, THE Agent SHALL create `artifacts/runbooks/postgres/issue-name.md` using template
5. WHEN distillation completes, THE Agent SHALL commit structured runbook to same PR

### Requirement 13: Crash-Only Recovery for Qdrant

**User Story:** As a platform operator, I want Qdrant to be ephemeral, so that if it crashes, I can rebuild the index from `artifacts/` quickly.

**Reference Pattern:** ✅ ADR 002 (Qdrant as index, not store)

#### Acceptance Criteria

1. WHEN Qdrant is down, THE Agent SHALL still function (degraded mode using GitHub search API)
2. WHEN rebuilding Qdrant, THE Process SHALL re-index all files in `artifacts/` from Git
3. WHEN re-indexing, THE Process SHALL complete in < 5 minutes for typical `artifacts/` size
4. WHERE state is needed, THE State SHALL be ephemeral (no backups of Qdrant data)
5. WHEN Qdrant restarts, THE Agent SHALL automatically trigger full re-index

### Requirement 14: Agent Acceptance Testing

**User Story:** As a platform maintainer, I want the agent to prove it can maintain documentation correctly before deployment, so that I have confidence in the automation.

**Reference Pattern:** ⚠️ CUSTOM - Agent-driven testing workflow

#### Acceptance Criteria

1. WHEN acceptance testing runs, THE Agent SHALL move existing `docs/templates/` to `artifacts/templates/` (preserving Git history)
2. WHEN testing Twin Docs, THE Agent SHALL read `platform/04-apis/compositions/webservice.yaml` and create `artifacts/specs/webservice.md`
3. WHEN testing runbooks, THE Agent SHALL create sample runbook in `artifacts/runbooks/` from template
4. WHERE validation runs, THE Validation SHALL pass for all agent-created content
5. WHEN testing distillation, THE Agent SHALL read sample `docs/research/notes.md` and create corresponding `artifacts/` content

### Requirement 15: Monitoring and Observability

**User Story:** As a platform operator, I want to monitor agent activity and documentation health, so that I can identify issues early.

**Reference Pattern:** ✅ Kagent OpenTelemetry tracing

#### Acceptance Criteria

1. WHEN agent runs, THE Agent SHALL emit OpenTelemetry traces to observability stack
2. WHEN docs-mcp is invoked, THE Server SHALL emit metrics (tool invocation count, latency)
3. WHEN CI auto-fix occurs, THE Workflow SHALL log agent invocation and commit hash
4. WHERE Qdrant sync runs, THE Sync SHALL log indexed file count and duration
5. WHEN errors occur, THE Errors SHALL be sent to Robusta for alerting

### Requirement 16: Compatibility with Existing Specs

**User Story:** As a platform architect, I want the documentation automation system to work seamlessly with the bootstrap CLI and Crossplane API restructure, so that all platform specs are compatible.

**Reference Pattern:** ✅ `.kiro/specs/platform-bootstrap-cli/` and `.kiro/specs/repo-restructure-refactor/`

#### Acceptance Criteria

1. WHEN bootstrap CLI is documented, THE Documentation SHALL be in `artifacts/specs/platform-cli.md`
2. WHEN Crossplane APIs are documented, THE Documentation SHALL be in `artifacts/specs/{resource}.md` (Twin Docs)
3. WHEN both systems deploy, THE Deployment SHALL use ArgoCD sync waves (bootstrap first, then intelligence layer)
4. WHERE dependencies exist, THE Dependencies SHALL be documented in spec frontmatter
5. WHEN specs reference each other, THE References SHALL use relative links to `artifacts/`

### Requirement 17: Crossplane Pattern Compliance

**User Story:** As a platform architect, I want the intelligence layer to follow the same Crossplane patterns as platform APIs, so that there is no refactoring needed when repo-restructure completes.

**Reference Pattern:** ✅ platform-ref-multi-k8s (pipeline mode, upbound/build, Configuration package)

#### Acceptance Criteria

1. WHEN intelligence layer is packaged, THE Package SHALL be a Crossplane Configuration with `crossplane.yaml` metadata
2. WHEN components are deployed, THE Deployments SHALL use Compositions in Pipeline mode (not raw YAML)
3. WHEN build system is configured, THE System SHALL use upbound/build Makefile with makelib includes
4. WHERE directory structure exists, THE Structure SHALL follow `definitions/`, `compositions/`, `examples/`, `providers/`, `test/` pattern
5. WHEN Twin Docs reference compositions, THE References SHALL point to `compositions/*.yaml` files (not flat YAML)

### Requirement 18: Security and RBAC

**User Story:** As a security engineer, I want the agent to have least-privilege access, so that it cannot accidentally modify critical platform resources.

**Reference Pattern:** ✅ kyverno-mcp RBAC pattern

#### Acceptance Criteria

1. WHEN docs-mcp ServiceAccount is created, THE RBAC SHALL grant read-only access to Kubernetes resources
2. WHEN GitHub token is configured, THE Token SHALL have repo scope only (not admin permissions)
3. WHEN agent commits, THE Commits SHALL be signed with GPG key (verified commits)
4. WHERE secrets are needed, THE Secrets SHALL be stored in External Secrets Operator (not in Git)
5. WHEN RBAC is reviewed, THE Review SHALL confirm no cluster-admin or write permissions to `platform/`
