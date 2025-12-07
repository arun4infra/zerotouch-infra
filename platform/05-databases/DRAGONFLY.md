# Dragonfly Cache Provisioning

## Overview

Dragonfly (Redis-compatible) caches are provisioned via Crossplane compositions.

## Usage

### Create DragonflyInstance Claim

```yaml
apiVersion: database.bizmatters.io/v1alpha1
kind: DragonflyInstance
metadata:
  name: my-service-cache
  namespace: my-namespace
spec:
  size: medium                              # small, medium, large
  storageGB: 10                             # Storage size
  connectionSecretName: my-service-dragonfly # Secret for apps to use
```

## Connection Secret

Crossplane creates `connectionSecretName` secret with:

| Key | Value |
|-----|-------|
| `endpoint` | `{name}.{namespace}.svc.cluster.local` |
| `port` | `6379` |
| `password` | Auto-generated |

## Application Usage

```yaml
env:
  - name: DRAGONFLY_HOST
    valueFrom:
      secretKeyRef:
        name: my-service-dragonfly
        key: endpoint
  - name: DRAGONFLY_PORT
    valueFrom:
      secretKeyRef:
        name: my-service-dragonfly
        key: port
  - name: DRAGONFLY_PASSWORD
    valueFrom:
      secretKeyRef:
        name: my-service-dragonfly
        key: password
```

## Size Configurations

| Size | CPU Request | CPU Limit | Memory Request | Memory Limit |
|------|-------------|-----------|----------------|--------------|
| small | 250m | 1000m | 512Mi | 2Gi |
| medium | 500m | 2000m | 1Gi | 4Gi |
| large | 1000m | 4000m | 2Gi | 8Gi |

## Notes

- Password is auto-generated (no SSM required)
- Pods scheduled on nodes with label `workload-type=stateful`
- Tolerates `database=true:NoSchedule` taint
- Uses `local-path` storage class
- Data persisted to `/data` via PVC
