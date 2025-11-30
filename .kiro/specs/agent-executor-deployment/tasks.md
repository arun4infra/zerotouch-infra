# Implementation Plan

- [ ] 1. Update agent_executor service code for NATS architecture
  - Remove Vault integration and use environment variables for secrets
  - Add NATS consumer as background task in FastAPI lifespan
  - Update CloudEvent emission to publish to NATS instead of K_SINK
  - Update migration script to work in init container without kubectl
  - _Requirements: 1.1, 1.5, 2.1, 8.1, 13.1, 14.1_

- [ ] 1.1 Remove Vault integration from agent_executor
  - Delete `services/vault.py` module completely
  - Remove VaultClient imports from `api/main.py`
  - Update lifespan to read secrets from environment variables (POSTGRES_HOST, POSTGRES_PASSWORD, etc.)
  - Remove vault_client parameter from GraphBuilder initialization
  - _Requirements: 14.1, 14.2_

- [ ] 1.2 Create NATS consumer module
  - Create `services/nats_consumer.py` with NATSConsumer class
  - Implement async start() method that connects to NATS JetStream
  - Implement pull_subscribe with durable consumer "agent-executor-workers"
  - Implement process_message() that parses CloudEvent and executes agent
  - Implement publish_result() that publishes result CloudEvent to NATS
  - Add proper error handling and message acknowledgment
  - _Requirements: 1.2, 8.1, 8.5, 13.2, 13.3_

- [ ] 1.3 Update FastAPI lifespan to start NATS consumer
  - Add NATS consumer initialization in lifespan startup
  - Start NATS consumer as asyncio background task
  - Add NATS consumer shutdown in lifespan cleanup
  - Ensure NATS consumer uses same execution logic as HTTP endpoint
  - _Requirements: 1.1, 1.2, 13.2_

- [ ] 1.4 Update CloudEvent emission to publish to NATS
  - Modify CloudEventEmitter to publish to NATS instead of K_SINK HTTP POST
  - Update emit_completed() to publish to subject "agent.status.completed"
  - Update emit_failed() to publish to subject "agent.status.failed"
  - Remove K_SINK environment variable dependency
  - Add NATS_URL environment variable support
  - _Requirements: 8.3, 8.4, 13.4_

- [ ] 1.5 Update migration script for init container
  - Modify `scripts/ci/run-migrations.sh` to use psql directly
  - Remove kubectl exec commands
  - Read database credentials from environment variables
  - Ensure script works without cluster access
  - Add proper error handling and exit codes
  - _Requirements: 2.2, 2.3_

- [ ] 2. Update integration tests for NATS architecture
  - Update docker-compose.test.yml to use Dragonfly and add NATS
  - Remove K_SINK mocking from test fixtures
  - Add NATS result verification to existing HTTP endpoint test
  - Add new NATS consumer test case
  - _Requirements: 3.1, 3.2, 3.3, 4.1_

- [ ] 2.1 Update docker-compose.test.yml
  - Replace redis service with dragonfly service using dragonflydb/dragonfly:latest image
  - Keep port mapping 16380:6379 for compatibility
  - Add nats service with JetStream enabled (command: ["-js"])
  - Map NATS port 14222:4222
  - Add healthchecks for both services
  - _Requirements: 3.1, 3.2, 3.4_

- [ ] 2.2 Remove K_SINK mocking from integration tests
  - Delete mock_k_sink_http fixture from test_api.py
  - Remove all K_SINK HTTP POST assertions
  - Update test to verify NATS publishing instead
  - _Requirements: 8.3_

- [ ] 2.3 Add NATS result verification to HTTP endpoint test
  - Subscribe to NATS subject "agent.status.completed" before test execution
  - Verify result CloudEvent is published to NATS after execution
  - Validate CloudEvent structure (type, source, subject, data)
  - Validate job_id and result payload in CloudEvent data
  - _Requirements: 8.3, 8.4_

- [ ] 2.4 Add NATS consumer integration test
  - Create new test function test_nats_consumer_processing()
  - Publish CloudEvent to NATS subject "agent.execute.test"
  - Verify NATS consumer processes message (check logs or metrics)
  - Verify result CloudEvent published to "agent.status.completed"
  - Verify PostgreSQL checkpoints created with correct thread_id
  - Verify Dragonfly streaming events published
  - _Requirements: 1.2, 8.1, 8.2, 8.5_

- [ ] 2.5 Update integration test documentation
  - Update README.md to reflect Dragonfly and NATS usage
  - Update docker-compose startup instructions
  - Document NATS consumer test execution
  - Update validation criteria for NATS publishing
  - _Requirements: 3.1, 4.1_

- [ ] 3. Configure External Secrets and create ExternalSecret resources
  - Verify ESO is deployed (already in bootstrap/components/01-eso.yaml)
  - Verify ClusterSecretStore aws-parameter-store exists (already in platform/01-foundation/aws-secret-store.yaml)
  - Create ExternalSecret resources for PostgreSQL, Dragonfly, and LLM keys
  - _Requirements: 7.1, 7.2, 7.3, 19.1_

- [ ] 3.1 Verify ESO deployment
  - Verify ESO pods are running in external-secrets namespace
  - Verify ClusterSecretStore aws-parameter-store exists
  - Verify AWS credentials are configured in external-secrets namespace
  - _Requirements: 19.1, 19.2_

- [ ] 3.2 Create ExternalSecret for PostgreSQL credentials
  - Create `platform/03-intelligence/external-secrets/agent-executor-postgres-es.yaml`
  - Map AWS SSM paths: /zerotouch/prod/agent-executor/postgres/host, port, db, user, password
  - Target Kubernetes Secret: agent-executor-postgres
  - Reference ClusterSecretStore: aws-parameter-store
  - _Requirements: 7.3, 14.3_

- [ ] 3.3 Create ExternalSecret for Dragonfly credentials
  - Create `platform/03-intelligence/external-secrets/agent-executor-dragonfly-es.yaml`
  - Map AWS SSM paths: /zerotouch/prod/agent-executor/dragonfly/host, port, password
  - Target Kubernetes Secret: agent-executor-dragonfly
  - Reference ClusterSecretStore: aws-parameter-store
  - _Requirements: 7.4, 14.4_

- [ ] 3.4 Create ExternalSecret for LLM API keys
  - Create `platform/03-intelligence/external-secrets/agent-executor-llm-keys-es.yaml`
  - Map AWS SSM paths: /zerotouch/prod/agent-executor/openai_api_key, anthropic_api_key
  - Target Kubernetes Secret: agent-executor-llm-keys
  - Reference ClusterSecretStore: aws-parameter-store
  - _Requirements: 7.5, 14.5_

- [ ] 3.5 Configure secrets in AWS SSM Parameter Store
  - Use AWS CLI to create parameters in /zerotouch/prod/agent-executor/ path
  - Add all PostgreSQL credentials (host, port, db, user, password)
  - Add all Dragonfly credentials (host, port, password)
  - Add all LLM API keys (OpenAI, Anthropic)
  - Verify ESO syncs secrets to Kubernetes
  - _Requirements: 7.6_

- [ ] 4. Deploy NATS with JetStream and create AGENT_EXECUTION stream
  - Create NATS ArgoCD Application in bootstrap/components
  - Enable JetStream for persistent streaming
  - Create AGENT_EXECUTION stream via Kubernetes Job
  - _Requirements: 4.1, 4.2, 4.3, 20.1_

- [ ] 4.1 Create NATS ArgoCD Application
  - Create `bootstrap/components/01-nats.yaml` with NATS Helm chart
  - Enable JetStream in Helm values
  - Configure resources (512Mi memory, 250m CPU)
  - Deploy to nats namespace
  - Set sync-wave annotation to "0"
  - _Requirements: 20.1, 20.2, 20.3_

- [ ] 4.2 Create NATS stream initialization Job
  - Create Job manifest in platform/01-foundation/ or as part of NATS Application
  - Use natsio/nats-box:latest image
  - Run nats stream add command for AGENT_EXECUTION stream
  - Configure subjects: "agent.execute.*"
  - Set retention: 24 hours, storage: file, replicas: 1
  - _Requirements: 4.1, 4.2, 20.4, 20.5_

- [ ] 4.3 Verify NATS deployment
  - Check NATS pods are running in nats namespace
  - Verify JetStream is enabled
  - Verify AGENT_EXECUTION stream exists
  - Test publishing and consuming messages
  - _Requirements: 4.4_

- [ ] 5. Create Crossplane XRD and Composition for agent_executor
  - Define XAgentExecutor XRD in 04-apis layer
  - Create agent-executor-composition that provisions all resources
  - Enable 04-apis layer in ArgoCD
  - _Requirements: 12.1, 12.2, 21.1_

- [ ] 5.1 Create XAgentExecutor XRD
  - Create `platform/04-apis/definitions/xagentexecutors.yaml`
  - Define group: platform.bizmatters.io
  - Define kinds: XAgentExecutor (composite), AgentExecutor (claim)
  - Define spec fields: image, size, natsUrl, postgresConnectionSecret, dragonflyConnectionSecret, llmKeysSecret
  - Add validation for size enum (small, medium, large)
  - _Requirements: 21.1, 21.2, 21.3_

- [ ] 5.2 Create agent-executor Composition
  - Create `platform/04-apis/compositions/agent-executor-composition.yaml`
  - Define resources: Deployment, Service, KEDA ScaledObject, ServiceAccount
  - Map size parameter to resource limits (small/medium/large)
  - Configure init container for migrations
  - Configure main container with environment variables from secrets
  - _Requirements: 12.1, 21.4, 21.5_

- [ ] 5.3 Configure Deployment in Composition
  - Add init container that runs scripts/ci/run-migrations.sh
  - Add main container with agent_executor image
  - Mount secrets as environment variables (PostgreSQL, Dragonfly, LLM keys)
  - Set NATS_URL environment variable
  - Configure resource requests and limits based on size
  - Add liveness and readiness probes
  - _Requirements: 2.1, 2.5, 12.2_

- [ ] 5.4 Configure KEDA ScaledObject in Composition
  - Add KEDA ScaledObject resource
  - Configure NATS Stream scaler with stream: AGENT_EXECUTION
  - Set consumer group: agent-executor-workers
  - Configure scaling thresholds: scale up when lag > 5, scale down when lag < 1
  - Set min replicas: 1, max replicas: 10
  - _Requirements: 4.4, 4.5, 11.1, 11.2, 11.3, 12.4_

- [ ] 5.5 Configure Service and ServiceAccount in Composition
  - Add Service resource (ClusterIP, port 8080)
  - Add ServiceAccount resource
  - Configure labels and annotations per platform standards
  - _Requirements: 12.1, 17.1, 17.2_

- [ ] 5.6 Enable 04-apis layer
  - Rename `platform/04-apis.yaml.disabled` to `platform/04-apis.yaml`
  - Commit and push to Git
  - Verify ArgoCD syncs and deploys XRD and Composition
  - _Requirements: 21.6_

- [ ] 6. Deploy agent_executor instance in 03-intelligence layer
  - Create intelligence-deepagents namespace
  - Create AgentExecutor claim
  - Deploy via GitOps (commit and push)
  - _Requirements: 5.1, 5.2, 22.1_

- [ ] 6.1 Create intelligence-deepagents namespace
  - Create `platform/03-intelligence/namespace-intelligence-deepagents.yaml`
  - Add labels: layer=intelligence, category=deepagents
  - Follow namespace naming convention documentation
  - _Requirements: 5.1, 5.2, 5.4, 18.1, 18.4_

- [ ] 6.2 Create AgentExecutor claim
  - Create `platform/03-intelligence/agent-executor-claim.yaml`
  - Specify image: ghcr.io/arun4infra/agent-executor:v1.0.0
  - Set size: medium
  - Set natsUrl: nats://nats.nats.svc:4222
  - Reference secrets: agent-executor-postgres, agent-executor-dragonfly, agent-executor-llm-keys
  - _Requirements: 22.1, 22.2, 22.3_

- [ ] 6.3 Deploy via GitOps
  - Commit all 03-intelligence manifests to Git
  - Push to repository
  - Verify ArgoCD syncs and Crossplane provisions resources
  - Verify Deployment, Service, KEDA ScaledObject are created
  - _Requirements: 6.1, 6.2, 15.1_

- [ ] 6.4 Verify deployment
  - Check agent-executor pods are running in intelligence-deepagents namespace
  - Verify init container completed migrations successfully
  - Verify main container started and NATS consumer is running
  - Check logs for successful NATS connection
  - Verify KEDA ScaledObject is monitoring NATS queue
  - _Requirements: 2.3, 11.5, 16.1_

- [ ] 7. Test end-to-end deployment
  - Publish test CloudEvent to NATS
  - Verify agent-executor processes message
  - Verify result published to NATS
  - Verify KEDA autoscaling works
  - _Requirements: 8.1, 11.1_

- [ ] 7.1 Publish test CloudEvent to NATS
  - Use nats CLI or test script to publish CloudEvent
  - Publish to subject: agent.execute.test-job-123
  - Include valid JobExecutionEvent payload
  - _Requirements: 8.1, 8.2_

- [ ] 7.2 Verify agent execution
  - Check agent-executor logs for message processing
  - Verify PostgreSQL checkpoints created
  - Verify Dragonfly streaming events published
  - Verify result CloudEvent published to agent.status.completed
  - _Requirements: 8.5, 9.1, 10.1_

- [ ] 7.3 Verify KEDA autoscaling
  - Publish multiple messages to NATS (>5)
  - Verify KEDA scales up agent-executor pods
  - Wait for queue to drain
  - Verify KEDA scales down to min replicas
  - _Requirements: 11.1, 11.2, 11.3, 11.4_

- [ ] 7.4 Verify health and metrics endpoints
  - Check /health endpoint returns 200 OK
  - Check /ready endpoint validates dependencies
  - Check /metrics endpoint exposes Prometheus metrics
  - Verify metrics include NATS-specific counters
  - _Requirements: 16.1, 16.2, 16.3_

- [ ] 8. Document deployment and create namespace naming convention
  - Create namespace naming convention documentation
  - Update platform documentation with agent_executor deployment
  - Document GitOps workflow for image updates
  - _Requirements: 18.1, 18.2_

- [ ] 8.1 Create namespace naming convention documentation
  - Create `docs/standards/namespace-naming-convention.md`
  - Document pattern: {layer}-{category}
  - Provide examples: intelligence-deepagents, databases-primary
  - Document required labels: layer, category
  - Explain rationale and benefits
  - _Requirements: 18.1, 18.2, 18.3, 18.5_

- [ ] 8.2 Update platform documentation
  - Document agent_executor deployment in platform overview
  - Add agent_executor to service catalog
  - Document Crossplane XRD usage
  - Document ESO secret management workflow
  - _Requirements: 6.5, 15.2_

- [ ] 8.3 Document GitOps workflow for updates
  - Document how to update agent_executor image
  - Provide example: Edit claim YAML, commit, push
  - Document rollback procedure
  - Emphasize no shell scripts for deployment
  - _Requirements: 6.1, 6.5, 22.5_

- [ ] 9. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.
