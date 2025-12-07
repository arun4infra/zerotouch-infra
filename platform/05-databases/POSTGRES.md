# PostgreSQL (CNPG) Database Provisioning

## Overview

PostgreSQL databases are provisioned using CloudNative-PG (CNPG) via Crossplane compositions.

**Important**: This follows CNPG security best practices:
- Uses **application users** (not postgres superuser)
- `enableSuperuserAccess` is **disabled** (default)
- Credentials are provided via SSM → ExternalSecret → CNPG initdb.secret

## Architecture

```
SSM Parameter Store
    ↓ (ExternalSecret syncs)
Kubernetes Secret (basic-auth type)
    ↓ (CNPG reads during bootstrap)
CNPG Cluster (creates app user + database)
    ↓ (Composition copies credentials)
Connection Secret (for applications)
```

## Usage

### 1. Configure SSM Parameters

```bash
# In .env.ssm (not committed to git)
/zerotouch/prod/my-service/postgres/user=my_service_user
/zerotouch/prod/my-service/postgres/password=<secure-password>

# Inject to SSM
./scripts/bootstrap/08-inject-ssm-parameters.sh
```

**Important**: The username should be an application-specific user (e.g., `agent_executor`), NOT `postgres`.

### 2. Create Credentials Secret (ExternalSecret)

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-service-db-credentials
  namespace: my-namespace
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-parameter-store
    kind: ClusterSecretStore
  target:
    name: my-service-db-credentials
    creationPolicy: Owner
    template:
      type: kubernetes.io/basic-auth
  data:
    - secretKey: username
      remoteRef:
        key: /zerotouch/prod/my-service/postgres/user
    - secretKey: password
      remoteRef:
        key: /zerotouch/prod/my-service/postgres/password
```

**Note**: The secret MUST be `kubernetes.io/basic-auth` type with `username` and `password` keys.

### 3. Create PostgresInstance Claim

```yaml
apiVersion: database.bizmatters.io/v1alpha1
kind: PostgresInstance
metadata:
  name: my-service-db
  namespace: my-namespace
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  size: medium                                    # small, medium, large
  version: "16"                                   # PostgreSQL version
  storageGB: 20                                   # Storage size
  databaseName: my_service_db                     # Application database name
  databaseOwner: my_service_user                  # Must match username in credentials secret
  connectionSecretName: my-service-postgres       # Secret for apps to use
  credentialsSecretName: my-service-db-credentials # SSM credentials secret
```

**Critical**: `databaseOwner` MUST match the `username` in `credentialsSecretName`.

## Connection Secret

Crossplane creates `connectionSecretName` secret with:

| Key | Value |
|-----|-------|
| `endpoint` | `{name}-rw.{namespace}.svc.cluster.local` |
| `port` | `5432` |
| `database` | Value from `databaseName` |
| `username` | From credentials secret |
| `password` | From credentials secret |

## Application Usage

```yaml
env:
  - name: POSTGRES_HOST
    valueFrom:
      secretKeyRef:
        name: my-service-postgres
        key: endpoint
  - name: POSTGRES_DB
    valueFrom:
      secretKeyRef:
        name: my-service-postgres
        key: database
  - name: POSTGRES_USER
    valueFrom:
      secretKeyRef:
        name: my-service-postgres
        key: username
  - name: POSTGRES_PASSWORD
    valueFrom:
      secretKeyRef:
        name: my-service-postgres
        key: password
```

## Size Configurations

| Size | CPU Request | CPU Limit | Memory Request | Memory Limit |
|------|-------------|-----------|----------------|--------------|
| small | 250m | 1000m | 256Mi | 1Gi |
| medium | 500m | 2000m | 512Mi | 2Gi |
| large | 1000m | 4000m | 1Gi | 4Gi |

## Complete Example: agent-executor

### SSM Parameters (.env.ssm)

```bash
/zerotouch/prod/agent-executor/postgres/user=agent_executor
/zerotouch/prod/agent-executor/postgres/password=<secure-password>
```

### ExternalSecret

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: agent-executor-db-credentials
  namespace: databases
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-parameter-store
    kind: ClusterSecretStore
  target:
    name: agent-executor-db-credentials
    creationPolicy: Owner
    template:
      type: kubernetes.io/basic-auth
  data:
    - secretKey: username
      remoteRef:
        key: /zerotouch/prod/agent-executor/postgres/user
    - secretKey: password
      remoteRef:
        key: /zerotouch/prod/agent-executor/postgres/password
```

### PostgresInstance Claim

```yaml
apiVersion: database.bizmatters.io/v1alpha1
kind: PostgresInstance
metadata:
  name: agent-executor-db
  namespace: databases
spec:
  size: medium
  version: "16"
  storageGB: 20
  databaseName: agent_executor_db_prod
  databaseOwner: agent_executor
  connectionSecretName: agent-executor-postgres
  credentialsSecretName: agent-executor-db-credentials
```

## How It Works (CNPG Pattern)

1. **ExternalSecret** syncs credentials from SSM to a `kubernetes.io/basic-auth` secret
2. **CNPG initdb.secret** reads the secret during cluster bootstrap:
   - Creates the database specified in `databaseName`
   - Creates an unprivileged user from `username` in the secret
   - Sets the password from `password` in the secret
   - Makes the user the owner of the database
3. **Composition** creates a connection secret copying credentials for applications

**Why not use postgres superuser?**
- CNPG recommends `enableSuperuserAccess: false` (default) for security
- The postgres user has no password - only local trust authentication
- Application users are unprivileged and safer for application access
- This follows the microservice pattern where apps don't need superuser access

## Notes

- Database pods scheduled on nodes with label `workload.bizmatters.dev/databases=true`
- Uses `local-path` storage class
- CNPG also creates `{cluster}-app` secret with the same credentials (for reference)
