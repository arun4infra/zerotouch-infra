# Requirements Document

## Introduction

This specification defines the requirements for migrating the agent_executor service from the bizmatters monorepo (Knative-based) to the bizmatters-infra platform (Crossplane + KEDA-based). The agent_executor is a Python-based LangGraph agent execution service that processes agent execution requests via NATS messaging, maintains state in PostgreSQL, and streams real-time events via Dragonfly (Redis-compatible cache).

The migration transforms the service from a Knative HTTP-based architecture to a NATS consumer-based architecture, replacing Vault with External Secrets Operator (ESO) for secret management, and deploying via Crossplane compositions following the platform's GitOps principles.

## Glossary

- **Agent Executor**: A Python service that executes LangGraph agents with stateful checkpointing
- **NATS**: Lightweight messaging system for event-driven communication
- **NATS Consumer**: A process that subscribes to NATS subjects and processes messages
- **KEDA**: Kubernetes Event-Driven Autoscaling for scaling based on NATS queue depth
- **Dragonfly**: Modern Redis-compatible in-memory data store used for real-time event streaming
- **PostgreSQL**: Relational database for LangGraph checkpoint persistence
- **ESO**: External Secrets Operator - Kubernetes operator that syncs secrets from external sources
- **AWS SSM Parameter Store**: AWS Systems Manager Parameter Store for secure secret storage
- **Crossplane**: Infrastructure-as-Code tool for provisioning Kubernetes resources declaratively
- **ArgoCD**: GitOps continuous delivery tool that syncs cluster state with Git
- **XRD**: Crossplane Composite Resource Definition - defines what developers can request
- **Composition**: Crossplane template that defines how to provision resources
- **Tier 3 Scripts**: Service-internal atomic scripts owned by backend developers
- **Tier 2 Scripts**: Platform orchestration scripts owned by DevOps engineers
- **CloudEvents**: Standardized event format for cross-platform event communication
- **LangGraph**: Framework for building stateful, multi-actor applications with LLMs
- **Init Container**: Kubernetes container that runs before main container starts
- **App-of-Apps**: ArgoCD pattern for managing multiple applications hierarchically

## Requirements

### Requirement 1

**User Story:** As a backend developer, I want agent_executor to support both HTTP and NATS invocation patterns, so that the service can handle direct HTTP requests for testing and NATS messages for production workloads.

#### Acceptance Criteria

1. THE agent_executor service SHALL run as a single Python process with both HTTP server and NATS consumer
2. WHEN the service starts THEN the system SHALL establish a NATS connection and start consuming messages in a background task
3. THE service SHALL keep the existing HTTP CloudEvent endpoint at POST / for direct invocation
4. THE service SHALL expose HTTP endpoints for /health, /ready, and /metrics on port 8080
5. WHEN a NATS message arrives THEN the system SHALL parse it as a CloudEvent and execute the agent using the same logic as the HTTP endpoint

### Requirement 2

**User Story:** As a platform operator, I want database migrations to run automatically before the service starts, so that schema changes are applied without manual intervention.

#### Acceptance Criteria

1. THE deployment SHALL include a Kubernetes init container that runs database migrations
2. THE init container SHALL execute the scripts/ci/run-migrations.sh script
3. WHEN migrations complete successfully THEN the main container SHALL start
4. IF migrations fail THEN the pod SHALL not start and SHALL report the error
5. THE init container SHALL use the same database credentials as the main container

### Requirement 3

**User Story:** As a backend developer, I want integration tests to use Dragonfly instead of Redis, so that tests match the production environment.

#### Acceptance Criteria

1. THE integration test docker-compose.test.yml SHALL use Dragonfly container instead of Redis
2. THE Python code SHALL continue using the redis library for Dragonfly connectivity
3. WHEN integration tests run THEN the system SHALL connect to Dragonfly on localhost:16380
4. THE Dragonfly container SHALL be Redis-compatible and support pub/sub operations
5. THE test fixtures SHALL verify Dragonfly connectivity before running tests

### Requirement 4

**User Story:** As a platform operator, I want NATS stream configuration to follow industry standards for development environments, so that the setup is maintainable and scalable.

#### Acceptance Criteria

1. THE NATS stream SHALL be named AGENT_EXECUTION
2. THE service SHALL subscribe to subject pattern agent.execute.*
3. THE consumer group SHALL be named agent-executor-workers
4. THE KEDA ScaledObject SHALL scale up when queue depth exceeds 5 messages
5. THE KEDA ScaledObject SHALL scale down when queue depth is less than 1 message

### Requirement 5

**User Story:** As a platform operator, I want agent_executor deployed in the intelligence-deepagents namespace, so that it aligns with the App-of-Apps ArgoCD structure.

#### Acceptance Criteria

1. THE agent_executor service SHALL be deployed in the intelligence-deepagents namespace
2. THE namespace SHALL be created automatically if it does not exist
3. THE ArgoCD Application SHALL be grouped under the intelligence App-of-Apps
4. THE namespace SHALL follow the pattern intelligence-{category} for workload organization
5. WHERE cross-namespace communication is required THEN the system SHALL configure appropriate network policies

### Requirement 6

**User Story:** As a platform operator, I want agent_executor deployment to follow pure GitOps principles, so that all changes are auditable and the system maintains "Zero-Touch" operation.

#### Acceptance Criteria

1. THE deployment process SHALL be triggered by committing changes to Git, not by executing scripts
2. WHEN a developer updates the image tag in the AgentExecutor claim THEN ArgoCD SHALL automatically sync the changes
3. THE Tier 3 build script SHALL remain at bizmatters/services/agent_executor/scripts/ci/build.sh for CI image building
4. THE system SHALL NOT use shell scripts for deployment orchestration (violates GitOps principles)
5. WHERE image updates are needed THEN developers SHALL edit platform/03-intelligence/agent-executor-claim.yaml and commit to Git

### Requirement 7

**User Story:** As a security engineer, I want secrets managed via External Secrets Operator (ESO), so that credentials are stored securely in AWS SSM Parameter Store and synced automatically to the cluster.

#### Acceptance Criteria

1. THE system SHALL use External Secrets Operator (ESO) for secret management, not SOPS-encrypted files
2. THE system SHALL create separate ExternalSecret resources for PostgreSQL, Dragonfly, and LLM API keys
3. THE PostgreSQL ExternalSecret SHALL be named agent-executor-postgres-es.yaml and reference AWS SSM Parameter Store paths
4. THE Dragonfly ExternalSecret SHALL be named agent-executor-dragonfly-es.yaml and reference AWS SSM Parameter Store paths
5. THE LLM API keys ExternalSecret SHALL be named agent-executor-llm-keys-es.yaml and reference AWS SSM Parameter Store paths
6. WHERE a secret is rotated THEN the operator SHALL update it in AWS SSM Parameter Store and ESO SHALL sync automatically
7. THE ExternalSecret manifests SHALL be stored in platform/03-intelligence/external-secrets/ directory

### Requirement 8

**User Story:** As a backend developer, I want agent_executor to process CloudEvents from NATS messages, so that the service integrates with the platform's event-driven architecture.

#### Acceptance Criteria

1. WHEN a NATS message arrives THEN the system SHALL parse it as a CloudEvent
2. THE CloudEvent data SHALL contain a JobExecutionEvent with job_id and agent_definition
3. WHEN execution completes THEN the system SHALL publish a result CloudEvent to NATS
4. THE result CloudEvent SHALL be published to subject agent.status.completed or agent.status.failed
5. THE system SHALL acknowledge NATS messages only after successful processing

### Requirement 9

**User Story:** As a backend developer, I want agent_executor to persist execution state in PostgreSQL, so that agent executions can be resumed after failures.

#### Acceptance Criteria

1. WHEN an agent execution starts THEN the system SHALL create a checkpoint in PostgreSQL
2. THE system SHALL use the job_id as the thread_id for LangGraph checkpointing
3. WHEN execution progresses THEN the system SHALL update checkpoints incrementally
4. IF the service restarts THEN the system SHALL resume executions from the last checkpoint
5. THE system SHALL connect to PostgreSQL using credentials from Kubernetes Secrets

### Requirement 10

**User Story:** As a backend developer, I want agent_executor to stream real-time events via Dragonfly, so that clients can monitor execution progress.

#### Acceptance Criteria

1. WHEN an agent execution produces events THEN the system SHALL publish to Dragonfly pub/sub channels
2. THE system SHALL use channel pattern langgraph:stream:{thread_id}
3. WHEN execution completes THEN the system SHALL publish an end event
4. THE system SHALL support streaming of LLM tokens, tool calls, and state transitions
5. THE system SHALL connect to Dragonfly using credentials from Kubernetes Secrets

### Requirement 11

**User Story:** As a platform operator, I want agent_executor to autoscale based on NATS queue depth, so that the service handles variable workloads efficiently.

#### Acceptance Criteria

1. WHEN NATS queue depth exceeds 5 messages THEN the system SHALL scale up agent_executor pods
2. WHEN NATS queue depth is less than 1 message THEN the system SHALL scale down to minimum replicas
3. THE system SHALL support scaling from 1 to 10 replicas
4. WHEN scaling occurs THEN the system SHALL maintain in-flight message processing
5. THE system SHALL use KEDA ScaledObject with NATS stream scaler

### Requirement 12

**User Story:** As a platform operator, I want agent_executor deployed via Crossplane compositions, so that the service follows platform standards and can be managed declaratively.

#### Acceptance Criteria

1. WHEN a developer creates a WebService claim THEN the system SHALL provision a Deployment, Service, KEDA ScaledObject, ServiceAccount, and NetworkPolicy
2. WHEN the WebService claim specifies resource size THEN the system SHALL map size to appropriate CPU and memory limits
3. WHEN the WebService claim is deleted THEN the system SHALL remove all provisioned resources
4. THE system SHALL support small, medium, and large size configurations with predefined resource allocations
5. WHERE the service requires NATS connectivity THEN the system SHALL configure appropriate environment variables and network policies

### Requirement 13

**User Story:** As a backend developer, I want agent_executor code modifications to support NATS consumer as a background task, so that the service can process messages from both HTTP and NATS sources.

#### Acceptance Criteria

1. THE agent_executor SHALL add a new services/nats_consumer.py module for NATS message consumption
2. THE NATS consumer SHALL run as an asyncio background task started by FastAPI lifespan
3. THE NATS consumer SHALL call the same process_execution_request function as the HTTP endpoint
4. THE NATS consumer SHALL publish result CloudEvents back to NATS
5. THE scripts/ci/run.sh SHALL start uvicorn which initializes both HTTP server and NATS consumer

### Requirement 14

**User Story:** As a backend developer, I want Vault client code removed from agent_executor, so that the service uses Kubernetes Secrets managed by External Secrets Operator.

#### Acceptance Criteria

1. THE agent_executor SHALL remove the services/vault.py module completely
2. THE api/main.py SHALL read secrets from environment variables populated by Kubernetes Secret mounts
3. THE system SHALL mount PostgreSQL credentials from secrets created by agent-executor-postgres ExternalSecret
4. THE system SHALL mount Dragonfly credentials from secrets created by agent-executor-dragonfly ExternalSecret
5. THE system SHALL mount LLM API keys from secrets created by agent-executor-llm-keys ExternalSecret
6. THE Kubernetes Secrets SHALL be automatically created and synced by ESO from GitHub Secrets

### Requirement 15

**User Story:** As a platform operator, I want agent_executor deployment managed by ArgoCD, so that the service follows GitOps principles.

#### Acceptance Criteria

1. WHEN Crossplane claims are committed to Git THEN ArgoCD SHALL sync them to the cluster
2. WHEN the service configuration changes THEN ArgoCD SHALL detect and apply updates
3. IF sync fails THEN ArgoCD SHALL report the error and maintain previous state
4. THE system SHALL support automated sync with self-healing enabled
5. THE system SHALL provide sync waves for ordered deployment of dependencies

### Requirement 16

**User Story:** As a backend developer, I want agent_executor to expose health and metrics endpoints, so that the platform can monitor service health.

#### Acceptance Criteria

1. THE service SHALL expose a /health endpoint for liveness probes on port 8080
2. THE service SHALL expose a /ready endpoint for readiness probes on port 8080
3. THE service SHALL expose a /metrics endpoint in Prometheus format on port 8080
4. WHEN the service is unhealthy THEN Kubernetes SHALL restart the pod
5. WHEN the service is not ready THEN Kubernetes SHALL not route traffic to the pod

### Requirement 17

**User Story:** As a platform operator, I want agent_executor to follow platform naming and labeling conventions, so that resources are discoverable and manageable.

#### Acceptance Criteria

1. THE system SHALL apply standard labels: app.kubernetes.io/name, app.kubernetes.io/component, app.kubernetes.io/version
2. THE system SHALL use consistent naming: {service-name}-{resource-type}
3. THE system SHALL tag container images with Git commit SHA
4. THE system SHALL annotate resources with ArgoCD sync metadata
5. THE system SHALL support querying resources by standard label selectors

### Requirement 18

**User Story:** As a platform operator, I want a documented namespace naming convention, so that all namespaces follow a consistent pattern with proper metadata.

#### Acceptance Criteria

1. THE system SHALL document the namespace naming convention at docs/standards/namespace-naming-convention.md
2. THE naming pattern SHALL be {layer}-{category} (e.g., intelligence-deepagents, databases-primary)
3. ALL namespaces SHALL include labels: layer and category for organizational metadata
4. THE agent_executor namespace SHALL be named intelligence-deepagents following this convention
5. THE documentation SHALL provide examples and rationale for the naming pattern

### Requirement 19

**User Story:** As a platform operator, I want External Secrets Operator deployed in the foundation layer, so that all services can use ESO for secret management.

#### Acceptance Criteria

1. THE External Secrets Operator SHALL be deployed via bootstrap/components/01-eso.yaml
2. THE ESO deployment SHALL use the official Helm chart from external-secrets.io
3. THE system SHALL configure a ClusterSecretStore named aws-parameter-store that references AWS SSM Parameter Store as the backend
4. THE ClusterSecretStore SHALL use AWS IAM credentials for authentication
5. WHERE services need secrets THEN they SHALL create ExternalSecret resources that reference the ClusterSecretStore

### Requirement 20

**User Story:** As a platform operator, I want NATS deployed in the foundation layer with JetStream enabled, so that agent_executor can consume messages for event-driven execution.

#### Acceptance Criteria

1. THE NATS server SHALL be deployed via bootstrap/components/01-nats.yaml using the official NATS Helm chart
2. THE NATS deployment SHALL enable JetStream for persistent streaming
3. THE NATS server SHALL be deployed in a dedicated nats namespace
4. THE system SHALL create the AGENT_EXECUTION stream via a Kubernetes Job
5. THE AGENT_EXECUTION stream SHALL be configured before agent_executor deployment to enable KEDA scaling

### Requirement 21

**User Story:** As a platform architect, I want agent_executor defined as a Crossplane XRD in the 04-apis layer, so that it follows the platform's composition pattern for service deployment.

#### Acceptance Criteria

1. THE XRD SHALL be defined at platform/04-apis/definitions/xagentexecutors.yaml
2. THE XRD SHALL use group platform.bizmatters.io with kind XAgentExecutor and claim kind AgentExecutor
3. THE XRD spec SHALL include fields: image, size (small/medium/large), natsUrl, postgresConnectionSecret, dragonflyConnectionSecret, llmKeysSecret
4. THE Composition SHALL be defined at platform/04-apis/compositions/agent-executor-composition.yaml
5. THE Composition SHALL create: Deployment (with init container), Service, KEDA ScaledObject, ServiceAccount
6. THE 04-apis layer SHALL be enabled by renaming platform/04-apis.yaml.disabled to platform/04-apis.yaml

### Requirement 22

**User Story:** As a platform operator, I want the agent_executor instance (claim) deployed in the 03-intelligence layer, so that it is co-located with other intelligence workloads.

#### Acceptance Criteria

1. THE AgentExecutor claim SHALL be defined at platform/03-intelligence/agent-executor-claim.yaml
2. THE claim SHALL specify the container image, size, and secret references
3. THE claim SHALL be deployed in the intelligence-deepagents namespace
4. THE namespace definition SHALL be at platform/03-intelligence/namespace-intelligence-deepagents.yaml
5. WHERE the image needs updating THEN developers SHALL edit the claim YAML and commit to Git (no scripts)
