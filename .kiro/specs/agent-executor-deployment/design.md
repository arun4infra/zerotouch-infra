# Design Document: Agent Executor Deployment

## 1. Overview

This design document describes the architecture for migrating the agent_executor service from the bizmatters monorepo (Knative-based) to the bizmatters-infra platform using Crossplane compositions, KEDA autoscaling, and External Secrets Operator (ESO) for secret management.

### 1.1 Design Goals

1. **Zero-Touch Operation**: All deployment changes via Git commits, no manual kubectl commands
2. **GitOps Compliance**: ArgoCD manages all infrastructure state
3. **Solo Founder Simplicity**: Use ESO with AWS SSM Parameter Store (no local encryption tools)
4. **Event-Driven Architecture**: NATS-based message consumption with KEDA autoscaling
5. **Self-Service**: Developers deploy by editing claim YAML files

### 1.2 Architecture Principles

- **Separation of Concerns**: XRD definitions (04-apis) separate from instances (03-intelligence)
- **Declarative Infrastructure**: All resources defined as Crossplane compositions
- **Automatic Scaling**: KEDA scales based on NATS queue depth
- **Stateful Execution**: PostgreSQL for LangGraph checkpoints, Dragonfly for real-time streaming

## 2. System Architecture

### 2.1 High-Level Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         GitHub Repository                        │
│  ┌────────────────────┐         ┌─────────────────────────┐    │
│  │ AWS SSM Param      │         │ Git (YAML Manifests)    │    │
│  │ Store              │         │ - XRD Definitions       │    │
│  │ - DB Credentials   │         │ - Compositions          │    │
│  │ - API Keys         │         │ - Claims                │    │
│  └────────────────────┘         └─────────────────────────┘    │
│           │                              │                      │
└───────────┼──────────────────────────────┼───────────────────────┘
            │                              │
            │ ESO Syncs                    │ ArgoCD Syncs
            ▼                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster (Talos)                    │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              01-foundation (Sync Wave 0-1)                │  │
│  │  ┌─────────────┐  ┌──────────┐  ┌──────────────────┐    │  │
│  │  │ Crossplane  │  │   KEDA   │  │  External        │    │  │
│  │  │             │  │          │  │  Secrets         │    │  │
│  │  └─────────────┘  └──────────┘  │  Operator (ESO)  │    │  │
│  │                                  └──────────────────┘    │  │
│  │  ┌─────────────────────────────────────────────────┐    │  │
│  │  │ NATS (JetStream)                                │    │  │
│  │  │ - Stream: AGENT_EXECUTION                       │    │  │
│  │  │ - Subject: agent.execute.*                      │    │  │
│  │  └─────────────────────────────────────────────────┘    │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              04-apis (Sync Wave 1)                        │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │ XRD: XAgentExecutor                                │  │  │
│  │  │ - Group: platform.bizmatters.io                    │  │  │
│  │  │ - Claim: AgentExecutor                             │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │ Composition: agent-executor-composition            │  │  │
│  │  │ Creates:                                           │  │  │
│  │  │ - Deployment (with init container)                 │  │  │
│  │  │ - Service                                          │  │  │
│  │  │ - KEDA ScaledObject                                │  │  │
│  │  │ - ServiceAccount                                   │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │       03-intelligence (Sync Wave 3)                       │  │
│  │  Namespace: intelligence-deepagents                       │  │
│  │                                                            │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │ ExternalSecrets (ESO Resources)                    │  │  │
│  │  │ - agent-executor-postgres-es.yaml                  │  │  │
│  │  │ - agent-executor-dragonfly-es.yaml                 │  │  │
│  │  │ - agent-executor-llm-keys-es.yaml                  │  │  │
│  │  │   ↓ Creates K8s Secrets                            │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  │                                                            │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │ Claim: agent-executor-claim.yaml                   │  │  │
│  │  │ - image: ghcr.io/org/agent-executor:v1.2.3         │  │  │
│  │  │ - size: medium                                     │  │  │
│  │  │ - natsUrl: nats://nats.nats.svc:4222               │  │  │
│  │  │   ↓ Crossplane Provisions                          │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  │                                                            │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │ Deployment: agent-executor                         │  │  │
│  │  │ ┌────────────────────────────────────────────────┐ │  │  │
│  │  │ │ Init Container: run-migrations                 │ │  │  │
│  │  │ │ - Runs: scripts/ci/run-migrations.sh           │ │  │  │
│  │  │ │ - Connects to PostgreSQL                       │ │  │  │
│  │  │ └────────────────────────────────────────────────┘ │  │  │
│  │  │ ┌────────────────────────────────────────────────┐ │  │  │
│  │  │ │ Main Container: agent-executor                 │ │  │  │
│  │  │ │ - HTTP Server (port 8080)                      │ │  │  │
│  │  │ │ - NATS Consumer (background task)              │ │  │  │
│  │  │ │ - Env vars from Secrets                        │ │  │  │
│  │  │ └────────────────────────────────────────────────┘ │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  │                                                            │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │ KEDA ScaledObject                                  │  │  │
│  │  │ - Trigger: NATS Stream (AGENT_EXECUTION)           │  │  │
│  │  │ - Scale Up: queue depth > 5                        │  │  │
│  │  │ - Scale Down: queue depth < 1                      │  │  │
│  │  │ - Min Replicas: 1, Max Replicas: 10                │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              05-databases (Existing)                      │  │
│  │  Namespace: databases                                     │  │
│  │  ┌────────────────┐      ┌────────────────────────┐      │  │
│  │  │ PostgreSQL     │      │ Dragonfly (Redis)      │      │  │
│  │  │ postgres:16    │      │ dragonflydb/dragonfly  │      │  │
│  │  └────────────────┘      └────────────────────────┘      │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────┘
```

### 2.2 Data Flow

#### 2.2.1 Deployment Flow (GitOps)
1. Developer updates `agent-executor-claim.yaml` (e.g., new image tag)
2. Commits to Git and pushes
3. ArgoCD detects change and syncs
4. Crossplane reconciles the claim
5. Kubernetes Deployment updates with new image
6. Rolling update replaces pods

#### 2.2.2 Secret Management Flow (ESO)
1. Operator stores secrets in AWS SSM Parameter Store
2. ESO polls AWS SSM Parameter Store API
3. ESO creates/updates Kubernetes Secrets in intelligence-deepagents namespace
4. Pods mount secrets as environment variables
5. Application reads from environment variables

#### 2.2.3 Message Processing Flow (NATS)
1. External system publishes CloudEvent to NATS subject `agent.execute.job123`
2. NATS JetStream persists message in AGENT_EXECUTION stream
3. KEDA monitors queue depth
4. If depth > 5, KEDA scales up agent-executor pods
5. NATS consumer in agent-executor receives message
6. Parses CloudEvent → JobExecutionEvent
7. Builds LangGraph agent from definition
8. Executes agent with PostgreSQL checkpointing
9. Streams events to Dragonfly pub/sub
10. Publishes result CloudEvent to NATS
11. Acknowledges message (removes from queue)

## 3. Component Design

### 3.1 External Secrets Operator (ESO)

#### 3.1.1 ClusterSecretStore Configuration
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-parameter-store
spec:
  provider:
    aws:
      service: ParameterStore
      region: us-east-1
      auth:
        secretRef:
          accessKeyIDSecretRef:
            name: aws-access-token
            key: AWS_ACCESS_KEY_ID
            namespace: external-secrets
          secretAccessKeySecretRef:
            name: aws-access-token
            key: AWS_SECRET_ACCESS_KEY
            namespace: external-secrets
```

#### 3.1.2 ExternalSecret Resources
Three ExternalSecret resources map AWS SSM Parameter Store paths to Kubernetes Secrets:

**PostgreSQL Credentials:**
- AWS SSM Paths: `/zerotouch/prod/agent-executor/postgres/host`, `/zerotouch/prod/agent-executor/postgres/port`, etc.
- K8s Secret: `agent-executor-postgres`

**Dragonfly Credentials:**
- AWS SSM Paths: `/zerotouch/prod/agent-executor/dragonfly/host`, `/zerotouch/prod/agent-executor/dragonfly/port`, etc.
- K8s Secret: `agent-executor-dragonfly`

**LLM API Keys:**
- AWS SSM Paths: `/zerotouch/prod/agent-executor/openai_api_key`, `/zerotouch/prod/agent-executor/anthropic_api_key`
- K8s Secret: `agent-executor-llm-keys`

### 3.2 NATS Infrastructure

#### 3.2.1 NATS Deployment
- **Deployment**: `bootstrap/components/01-nats.yaml` (ArgoCD Application)
- **Helm Chart**: `nats/nats` (official chart)
- **Namespace**: `nats`
- **JetStream**: Enabled for persistent streaming
- **Resources**: 512Mi memory, 250m CPU (small deployment)

#### 3.2.2 Stream Configuration
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: nats-stream-init
  namespace: nats
spec:
  template:
    spec:
      containers:
      - name: nats-cli
        image: natsio/nats-box:latest
        command:
        - /bin/sh
        - -c
        - |
          nats stream add AGENT_EXECUTION \
            --subjects "agent.execute.*" \
            --retention limits \
            --max-msgs=-1 \
            --max-age=24h \
            --storage file \
            --replicas 1 \
            --discard old
```

**Stream Properties:**
- Name: `AGENT_EXECUTION`
- Subjects: `agent.execute.*`
- Retention: 24 hours
- Storage: File-based (persistent)
- Consumer Group: `agent-executor-workers`

### 3.3 Crossplane XRD and Composition

#### 3.3.1 XRD Definition
```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xagentexecutors.platform.bizmatters.io
spec:
  group: platform.bizmatters.io
  names:
    kind: XAgentExecutor
    plural: xagentexecutors
  claimNames:
    kind: AgentExecutor
    plural: agentexecutors
  versions:
    - name: v1alpha1
      served: true
      referenceable: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                image:
                  type: string
                  description: "Container image (e.g., ghcr.io/org/agent-executor:v1.0.0)"
                size:
                  type: string
                  description: "Resource size (small, medium, large)"
                  enum: [small, medium, large]
                  default: medium
                natsUrl:
                  type: string
                  description: "NATS server URL"
                  default: "nats://nats.nats.svc:4222"
                postgresConnectionSecret:
                  type: string
                  description: "Name of secret containing PostgreSQL credentials"
                  default: "agent-executor-postgres"
                dragonflyConnectionSecret:
                  type: string
                  description: "Name of secret containing Dragonfly credentials"
                  default: "agent-executor-dragonfly"
                llmKeysSecret:
                  type: string
                  description: "Name of secret containing LLM API keys"
                  default: "agent-executor-llm-keys"
              required:
                - image
```

#### 3.3.2 Composition Resources

The composition creates the following resources:

**1. ServiceAccount**
- Name: `agent-executor`
- Namespace: From claim
- Purpose: Pod identity for RBAC

**2. Deployment**
- Init Container: Runs database migrations
- Main Container: Agent executor service
- Environment variables from secrets
- Resource limits based on size parameter

**3. Service**
- Type: ClusterIP
- Port: 8080 (HTTP)
- Selector: `app: agent-executor`

**4. KEDA ScaledObject**
- Trigger: NATS Stream scaler
- Stream: `AGENT_EXECUTION`
- Consumer Group: `agent-executor-workers`
- Scaling thresholds:
  - Scale up: lag > 5 messages
  - Scale down: lag < 1 message
- Min replicas: 1
- Max replicas: 10

#### 3.3.3 Size-Based Resource Mapping

| Size   | CPU Request | CPU Limit | Memory Request | Memory Limit |
|--------|-------------|-----------|----------------|--------------|
| small  | 250m        | 1000m     | 512Mi          | 2Gi          |
| medium | 500m        | 2000m     | 1Gi            | 4Gi          |
| large  | 1000m       | 4000m     | 2Gi            | 8Gi          |

### 3.4 Application Architecture

#### 3.4.1 Service Structure (bizmatters/services/agent_executor)

```
agent_executor/
├── api/
│   └── main.py                    # FastAPI app (HTTP + NATS consumer)
├── core/
│   ├── builder.py                 # LangGraph agent builder
│   ├── executor.py                # Execution manager
│   └── ...
├── services/
│   ├── cloudevents.py             # CloudEvent parsing/emission
│   ├── redis.py                   # Dragonfly streaming client
│   ├── nats_consumer.py           # NEW: NATS consumer
│   └── vault.py                   # REMOVED
├── models/
│   └── events.py                  # JobExecutionEvent model
├── scripts/
│   └── ci/
│       ├── build.sh               # Docker image build
│       ├── run.sh                 # Service entrypoint
│       └── run-migrations.sh      # Database migrations
└── migrations/
    └── 001_create_checkpointer_tables.up.sql
```

#### 3.4.2 FastAPI Lifespan (api/main.py)

```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    logger.info("agent_executor_service_starting")
    
    # Read secrets from environment variables (no Vault)
    postgres_host = os.getenv("POSTGRES_HOST")
    postgres_password = os.getenv("POSTGRES_PASSWORD")
    dragonfly_host = os.getenv("DRAGONFLY_HOST")
    openai_api_key = os.getenv("OPENAI_API_KEY")
    
    # Initialize services
    redis_client = RedisClient(host=dragonfly_host, ...)
    execution_manager = ExecutionManager(redis_client, postgres_conn_str)
    
    # Start NATS consumer as background task
    nats_consumer = NATSConsumer(
        nats_url=os.getenv("NATS_URL"),
        stream_name="AGENT_EXECUTION",
        consumer_group="agent-executor-workers"
    )
    asyncio.create_task(nats_consumer.start())
    
    yield
    
    # Shutdown
    await nats_consumer.stop()
    redis_client.close()
```

#### 3.4.3 NATS Consumer (services/nats_consumer.py)

```python
class NATSConsumer:
    async def start(self):
        nc = await nats.connect(self.nats_url)
        js = nc.jetstream()
        
        # Create durable consumer
        consumer = await js.pull_subscribe(
            subject="agent.execute.*",
            durable="agent-executor-workers",
            stream="AGENT_EXECUTION"
        )
        
        while True:
            msgs = await consumer.fetch(batch=1, timeout=5)
            for msg in msgs:
                await self.process_message(msg)
                await msg.ack()
    
    async def process_message(self, msg):
        # Parse CloudEvent
        event_data = json.loads(msg.data)
        job_event = JobExecutionEvent(**event_data)
        
        # Execute agent (same logic as HTTP endpoint)
        result = await execute_agent(job_event)
        
        # Publish result CloudEvent back to NATS
        await self.publish_result(result)
```

#### 3.4.4 Migration Script (scripts/ci/run-migrations.sh)

Updated to work inside init container (no kubectl):

```bash
#!/bin/bash
set -e

# Read from environment variables (populated by secrets)
POSTGRES_HOST="${POSTGRES_HOST}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB}"
POSTGRES_USER="${POSTGRES_USER}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
POSTGRES_SCHEMA="${POSTGRES_SCHEMA:-agent_executor}"

# Run migrations using psql directly
for migration in /app/migrations/*.up.sql; do
  echo "Applying migration: $(basename "$migration")"
  
  PGPASSWORD="$POSTGRES_PASSWORD" psql \
    -h "$POSTGRES_HOST" \
    -p "$POSTGRES_PORT" \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" \
    -v ON_ERROR_STOP=1 \
    -c "SET search_path TO ${POSTGRES_SCHEMA};" \
    -f "$migration"
done
```

## 4. Deployment Workflow

### 4.1 Initial Deployment

**Step 1: Deploy Foundation (One-Time)**
```bash
# Enable 04-apis layer
git mv platform/04-apis.yaml.disabled platform/04-apis.yaml

# Commit and push
git add platform/04-apis.yaml
git commit -m "feat: Enable 04-apis layer for agent-executor"
git push
```

ArgoCD syncs and deploys:
- ESO (if not already deployed)
- NATS with JetStream
- XRD and Composition definitions

**Step 2: Configure Secrets in AWS SSM Parameter Store**
Use AWS CLI or Console to add parameters:
```bash
aws ssm put-parameter --name /zerotouch/prod/agent-executor/postgres/host --value "postgres.databases.svc.cluster.local" --type String
aws ssm put-parameter --name /zerotouch/prod/agent-executor/postgres/port --value "5432" --type String
aws ssm put-parameter --name /zerotouch/prod/agent-executor/postgres/db --value "langgraph_dev" --type String
aws ssm put-parameter --name /zerotouch/prod/agent-executor/postgres/user --value "postgres" --type String
aws ssm put-parameter --name /zerotouch/prod/agent-executor/postgres/password --value "<actual-password>" --type SecureString
aws ssm put-parameter --name /zerotouch/prod/agent-executor/dragonfly/host --value "dragonfly.databases.svc.cluster.local" --type String
aws ssm put-parameter --name /zerotouch/prod/agent-executor/dragonfly/port --value "6379" --type String
aws ssm put-parameter --name /zerotouch/prod/agent-executor/dragonfly/password --value "<actual-password>" --type SecureString
aws ssm put-parameter --name /zerotouch/prod/agent-executor/openai_api_key --value "sk-..." --type SecureString
aws ssm put-parameter --name /zerotouch/prod/agent-executor/anthropic_api_key --value "sk-ant-..." --type SecureString
```

**Step 3: Deploy Agent Executor Instance**
```bash
# Create claim file
cat > platform/03-intelligence/agent-executor-claim.yaml <<EOF
apiVersion: platform.bizmatters.io/v1alpha1
kind: AgentExecutor
metadata:
  name: agent-executor
  namespace: intelligence-deepagents
spec:
  image: ghcr.io/arun4infra/agent-executor:v1.0.0
  size: medium
  natsUrl: nats://nats.nats.svc:4222
  postgresConnectionSecret: agent-executor-postgres
  dragonflyConnectionSecret: agent-executor-dragonfly
  llmKeysSecret: agent-executor-llm-keys
EOF

git add platform/03-intelligence/
git commit -m "feat: Deploy agent-executor v1.0.0"
git push
```

ArgoCD syncs and Crossplane provisions all resources.

### 4.2 Updating the Service (Image Rollout)

**Developer Workflow:**
1. Build new image via CI: `bizmatters/services/agent_executor/scripts/ci/build.sh`
2. CI pushes image to registry: `ghcr.io/arun4infra/agent-executor:v1.1.0`
3. Developer updates claim:
   ```bash
   # Edit platform/03-intelligence/agent-executor-claim.yaml
   # Change: image: ghcr.io/arun4infra/agent-executor:v1.1.0
   
   git add platform/03-intelligence/agent-executor-claim.yaml
   git commit -m "chore: Update agent-executor to v1.1.0"
   git push
   ```
4. ArgoCD syncs
5. Crossplane updates Deployment
6. Kubernetes performs rolling update

**No shell scripts. Pure GitOps.**

### 4.3 Scaling Configuration

**Manual Scaling (Change Size):**
```yaml
# Edit claim
spec:
  size: large  # Change from medium to large
```

**Automatic Scaling (KEDA):**
- KEDA monitors NATS queue depth automatically
- Scales between 1-10 replicas based on load
- No manual intervention required

## 5. Observability

### 5.1 Metrics
- **Endpoint**: `/metrics` (Prometheus format)
- **Metrics**:
  - `agent_executor_jobs_total{status="completed|failed"}`
  - `agent_executor_job_duration_seconds`
  - `agent_executor_nats_messages_processed_total`
  - `agent_executor_nats_messages_failed_total`

### 5.2 Health Checks
- **Liveness**: `/health` (checks service health)
- **Readiness**: `/ready` (checks dependencies: PostgreSQL, Dragonfly, NATS)

### 5.3 Logging
- Structured JSON logs via structlog
- Correlation IDs: `trace_id`, `job_id`
- Log levels: INFO (default), DEBUG (verbose)

## 6. Security Considerations

### 6.1 Secret Management
- **Storage**: AWS SSM Parameter Store (encrypted at rest with KMS)
- **Access**: ESO uses AWS IAM credentials with minimal permissions
- **Rotation**: Update in AWS SSM, ESO syncs automatically
- **Scope**: Secrets scoped to intelligence-deepagents namespace

### 6.2 Network Policies
- Agent executor can access:
  - NATS (nats namespace)
  - PostgreSQL (databases namespace)
  - Dragonfly (databases namespace)
- Deny all other traffic by default

### 6.3 RBAC
- ServiceAccount: `agent-executor`
- Permissions: None required (no K8s API access needed)

## 7. Implementation Strategy

This section outlines the changes needed to deploy agent_executor to the bizmatters-infra platform using Crossplane, KEDA, and ESO.

### 7.1 Code Changes (bizmatters repo)

**Changes to agent_executor service:**
1. **Remove Vault Integration**
   - Delete `services/vault.py` completely
   - Remove VaultClient from `api/main.py`
   - Read secrets from environment variables instead

2. **Add NATS Consumer**
   - Create `services/nats_consumer.py` with NATS JetStream consumer
   - Start NATS consumer as asyncio background task in FastAPI lifespan
   - Reuse existing execution logic from HTTP endpoint

3. **Update Migration Script**
   - Modify `scripts/ci/run-migrations.sh` to use psql directly (not kubectl)
   - Script must work inside init container without cluster access

4. **Update Tests**
   - Change `docker-compose.test.yml` to use Dragonfly image instead of Redis
   - Ensure integration tests work with Dragonfly

### 7.2 Infrastructure Changes (bizmatters-infra repo)

**New platform components:**
1. **Foundation Layer (01-foundation)**
   - Deploy External Secrets Operator (ESO)
   - Deploy NATS with JetStream enabled
   - Create AGENT_EXECUTION stream via Job

2. **APIs Layer (04-apis)**
   - Enable layer by renaming `04-apis.yaml.disabled` → `04-apis.yaml`
   - Create XRD: `definitions/xagentexecutors.yaml`
   - Create Composition: `compositions/agent-executor-composition.yaml`

3. **Intelligence Layer (03-intelligence)**
   - Create namespace: `namespace-intelligence-deepagents.yaml`
   - Create ExternalSecrets (3 files for postgres, dragonfly, llm-keys)
   - Create claim: `agent-executor-claim.yaml`

### 7.3 Testing Strategy

#### 7.3.1 Unit Tests
**Location:** `bizmatters/services/agent_executor/tests/unit/`

**Changes:**
- ✅ Keep existing tests (test_builder.py, test_cloudevents.py, etc.)
- ❌ Delete `test_vault.py` (Vault removed)
- ➕ Add `test_nats_consumer.py` (test NATS consumer logic)

**Scope:** Individual component logic with mocked dependencies

#### 7.3.2 Integration Tests (Focus of This Spec)
**Location:** `bizmatters/services/agent_executor/tests/integration/`

**Purpose:** Validate internal component integration with real infrastructure (PostgreSQL, Dragonfly, NATS) running locally via Docker Compose.

**Key Principles:**
- ✅ Test internal integration, NOT multi-system flows
- ✅ Use REAL PostgreSQL, Dragonfly, NATS via Docker Compose
- ✅ Use REAL LLM API calls to validate actual execution results
- ✅ External Observer Pattern (HTTP requests, no code imports)
- ✅ Load OPENAI_API_KEY from .env file for real agent execution

**Infrastructure Setup:**

Update `docker-compose.test.yml`:
```yaml
services:
  postgres:
    image: postgres:16-alpine
    container_name: agent-executor-test-postgres
    environment:
      POSTGRES_USER: test_user
      POSTGRES_PASSWORD: test_pass
      POSTGRES_DB: test_db
    ports:
      - "15433:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U test_user"]
      interval: 5s
      timeout: 5s
      retries: 5

  dragonfly:  # CHANGED: Replace redis with dragonfly
    image: docker.dragonflydb.io/dragonflydb/dragonfly:latest
    container_name: agent-executor-test-dragonfly
    ports:
      - "16380:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]  # Dragonfly is Redis-compatible
      interval: 5s
      timeout: 5s
      retries: 5

  nats:  # NEW: Add NATS for testing NATS consumer
    image: nats:latest
    container_name: agent-executor-test-nats
    command: ["-js"]  # Enable JetStream
    ports:
      - "14222:4222"
    healthcheck:
      test: ["CMD", "nats", "server", "check", "jetstream"]
      interval: 5s
      timeout: 5s
      retries: 5
```

**Current State Analysis:**

The existing integration test (`test_api.py`) already:
- ✅ Uses REAL LLM API calls (loads OPENAI_API_KEY from .env)
- ✅ Uses REAL PostgreSQL via Docker Compose
- ✅ Tests HTTP CloudEvent endpoint

What needs to change:
- ❌ Currently uses Redis → Change to Dragonfly in docker-compose.test.yml
- ❌ Mocks K_SINK HTTP POST → Remove K_SINK mocking (Knative legacy)
- ❌ No NATS infrastructure → Add NATS to docker-compose.test.yml
- ❌ No NATS consumer tests → Add NATS message publishing and result verification

**Test Coverage:**

1. **HTTP Endpoint Tests** (Update Existing)
   - POST / with CloudEvent
   - Verify PostgreSQL checkpoints
   - Verify Dragonfly streaming (update from Redis)
   - **REMOVE**: K_SINK HTTP POST mocking
   - **ADD**: Verify result CloudEvent published to NATS (not K_SINK)

2. **NATS Consumer Tests** (NEW)
   - Publish CloudEvent to NATS subject `agent.execute.test`
   - Verify agent-executor consumes message via NATS consumer
   - Verify REAL LLM execution completes successfully
   - Verify result CloudEvent published to NATS subject `agent.status.completed`
   - Verify result contains actual agent output (not mocked)
   - Verify PostgreSQL checkpoints created with correct thread_id
   - Verify Dragonfly streaming events published

3. **Dragonfly Compatibility Tests** (NEW)
   - Verify Dragonfly pub/sub works with existing Redis client
   - Verify channel naming convention
   - Verify event structure

**Test Execution:**
```bash
cd bizmatters/services/agent_executor

# Start test infrastructure
docker-compose -f tests/integration/docker-compose.test.yml up -d

# Wait for health checks
sleep 10

# Run integration tests
pytest tests/integration/ -v -s

# Cleanup
docker-compose -f tests/integration/docker-compose.test.yml down -v
```

**What Integration Tests Validate:**
- ✅ HTTP CloudEvent endpoint works
- ✅ NATS consumer receives and processes messages
- ✅ REAL LLM execution produces actual results (already working in current test)
- ✅ PostgreSQL checkpointing (thread_id = job_id)
- ✅ Dragonfly streaming (pub/sub channels) - updated from Redis
- ✅ Result CloudEvent published to NATS (replaces K_SINK HTTP POST)
- ✅ Error handling (graceful failures)
- ✅ W3C Trace Context propagation

**Migration from Current Test:**
The existing `test_api.py` already validates most functionality with REAL LLM calls. Changes needed:
1. Update `docker-compose.test.yml`: Replace `redis` service with `dragonfly`, add `nats` service
2. Remove K_SINK mocking: Delete `responses.post()` mock for K_SINK HTTP endpoint
3. Add NATS result verification: Subscribe to NATS subject and verify result CloudEvent
4. Add NATS consumer test: New test case that publishes to NATS and verifies end-to-end flow

**What Integration Tests Do NOT Validate:**
- ❌ Kubernetes deployment
- ❌ KEDA autoscaling
- ❌ ESO secret management
- ❌ Crossplane provisioning
- ❌ Multi-system flows (that's E2E scope)

#### 7.3.3 E2E Tests
**Status:** Out of scope for this specification. Will be addressed in future work.

**Purpose:** Validate complete deployment in Kubernetes with real NATS, KEDA, ESO, and Crossplane.

#### 7.3.4 Smoke Test
Deploy to production namespace, monitor metrics and logs for basic health validation.

## 8. Rollback Plan

### 8.1 Rollback Deployment
```bash
# Revert claim to previous image
git revert <commit-hash>
git push
```

ArgoCD syncs and rolls back to previous version.

### 8.2 Rollback Infrastructure
```bash
# Delete claim (keeps XRD/Composition)
kubectl delete agentexecutor agent-executor -n intelligence-deepagents

# Or revert entire Git commit
git revert <commit-hash>
git push
```

## 9. Future Enhancements

### 9.1 Multi-Tenancy
- Deploy multiple AgentExecutor instances with different configurations
- Separate NATS subjects per tenant
- Isolated namespaces per tenant

### 9.2 High Availability
- Increase NATS replicas (3-node cluster)
- PostgreSQL replication (when migrating to CNPG)
- Multi-region deployment

### 9.3 Advanced Scaling
- Custom KEDA metrics (e.g., job duration)
- Predictive scaling based on historical patterns
- Cost optimization with scale-to-zero during off-hours

## 10. References

- **Requirements**: `requirements.md`
- **Platform Overview**: `bizmatters-infra/docs/architecture/platform-overview.md`
- **Secret Management**: `bizmatters-infra/docs/architecture/secret-management.md`
- **Script Hierarchy**: `bizmatters/.claude/skills/standards/script-hierarchy-model.md`
- **External Secrets Operator**: https://external-secrets.io/
- **NATS JetStream**: https://docs.nats.io/nats-concepts/jetstream
- **KEDA**: https://keda.sh/docs/scalers/nats-jetstream/
- **Crossplane**: https://docs.crossplane.io/
