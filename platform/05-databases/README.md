# Database Layer - Crossplane XRDs & Compositions

This ArgoCD Application manages **cluster-scoped** Crossplane database definitions only.

## Purpose

Defines the database platform API that applications can use to request databases.
Claims are created **in the application's namespace**, not here.

## Structure

```
platform/05-databases/
├── definitions/                # XRDs (cluster-scoped API definitions)
│   ├── postgres-xrd.yaml
│   └── dragonfly-xrd.yaml
└── compositions/               # Compositions (cluster-scoped provisioning logic)
    ├── postgres-composition.yaml
    └── dragonfly-composition.yaml
```

## What This Deploys

- **CompositeResourceDefinitions (XRDs)**: Define the API (e.g., `PostgresInstance`, `DragonflyInstance`)
- **Compositions**: Define how to provision databases when requested

## What This Does NOT Deploy

- ❌ No namespace creation
- ❌ No database instances (claims live with applications)
- ❌ No provider configs (managed in foundation layer)

## How It Works

### 1. Platform Team Defines (One Time - This Repo)
- **XRDs** (`definitions/`): Define what developers can request
- **Compositions** (`compositions/`): Define how to provision databases

### 2. Application Teams Request Databases (In Their Namespace)
Create a claim file **in your application's directory**:

**Example: `platform/03-intelligence/postgres-claim.yaml`**
```yaml
apiVersion: database.bizmatters.io/v1alpha1
kind: PostgresInstance
metadata:
  name: agent-db
  namespace: intelligence-platform  # Same namespace as your app
spec:
  size: medium      # small, medium, large
  version: "16"
  storageGB: 50
```

Crossplane automatically creates **in the same namespace**:
- StatefulSet (with node affinity, resources)
- Service (accessible at `agent-db.intelligence-platform.svc.cluster.local`)
- PVC (with correct storage class)
- Secret (`agent-db-secret` with credentials)

## Creating a New Database Instance

### PostgreSQL
```yaml
apiVersion: database.bizmatters.io/v1alpha1
kind: PostgresInstance
metadata:
  name: my-postgres
  namespace: my-app-namespace  # Your application's namespace
spec:
  size: small       # small: 256Mi-1Gi, medium: 512Mi-2Gi, large: 1Gi-4Gi
  version: "16"     # PostgreSQL version
  storageGB: 20     # Storage size (10-1000 GB)
```

### Dragonfly (Redis-compatible)
```yaml
apiVersion: database.bizmatters.io/v1alpha1
kind: DragonflyInstance
metadata:
  name: my-cache
  namespace: my-app-namespace  # Your application's namespace
spec:
  size: small       # small: 512Mi-2Gi, medium: 1Gi-4Gi, large: 2Gi-8Gi
  storageGB: 10     # Storage size (5-500 GB)
```

## Size Mappings

### PostgreSQL
| Size   | Memory Request | Memory Limit | CPU Request | CPU Limit | Default Storage |
|--------|---------------|--------------|-------------|-----------|-----------------|
| small  | 256Mi         | 1Gi          | 250m        | 1000m     | 20Gi            |
| medium | 512Mi         | 2Gi          | 500m        | 2000m     | 50Gi            |
| large  | 1Gi           | 4Gi          | 1000m       | 4000m     | 100Gi           |

### Dragonfly
| Size   | Memory Request | Memory Limit | CPU Request | CPU Limit | Default Storage |
|--------|---------------|--------------|-------------|-----------|-----------------|
| small  | 512Mi         | 2Gi          | 250m        | 1000m     | 10Gi            |
| medium | 1Gi           | 4Gi          | 500m        | 2000m     | 25Gi            |
| large  | 2Gi           | 8Gi          | 1000m       | 4000m     | 50Gi            |

## Connection Information

Crossplane creates the Service and Secret in the **SAME NAMESPACE** where you created the Claim.

### PostgreSQL
- **DNS**: `<instance-name>.<your-namespace>.svc.cluster.local:5432`
  - Example: `agent-db.intelligence-platform.svc.cluster.local:5432`
- **Credentials**: Secret `<instance-name>-secret` in `<your-namespace>`
  - `username`
  - `password`
  - `endpoint` (Use this for connecting)

### Dragonfly
- **DNS**: `<instance-name>.<your-namespace>.svc.cluster.local:6379`
  - Example: `my-cache.intelligence-platform.svc.cluster.local:6379`
- **Credentials**: Secret `<instance-name>-secret` in `<your-namespace>`
  - `password`

## Scaling

To scale an existing instance, edit the claim file in your application directory:

```yaml
# Edit platform/03-intelligence/postgres-claim.yaml
spec:
  size: large        # Change from small to large
  storageGB: 100     # Increase storage
```

Crossplane will automatically:
- Update StatefulSet resources
- Expand PVC (if supported by storage class)
- Maintain data integrity

## Architecture: Same Namespace Pattern

```
platform/03-intelligence/
├── namespace.yaml
├── postgres-claim.yaml          # Database claim lives with app
├── qdrant.yaml                  # App workload
└── agents/
    └── librarian-agent.yaml

Result in intelligence-platform namespace:
├── agent-db (StatefulSet)       # Created by Crossplane
├── agent-db (Service)           # Created by Crossplane
├── agent-db-secret (Secret)     # Created by Crossplane
├── qdrant (Deployment)          # App workload
└── librarian-agent (Pod)        # App workload
```

## Benefits Over Direct StatefulSets

1. **Self-Service**: Developers request databases with simple YAML
2. **Co-location**: Database lives in same namespace as application
3. **Standardization**: All instances follow platform standards
4. **Consistency**: No configuration drift
5. **Lifecycle Management**: Crossplane handles updates, deletions
6. **Abstraction**: Platform team controls implementation details
