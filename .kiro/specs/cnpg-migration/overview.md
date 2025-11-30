Here is the final **Enterprise-Grade CloudNativePG Specification**. This document incorporates all safety layers (GitOps, Storage, S3) to guarantee Zero Data Loss in a "Solo Founder" environment.

---

# Requirement Specification: CloudNativePG (Enterprise/Aerospace Grade)

## 1. Introduction
This document defines the strict configuration standards for PostgreSQL clusters within the `bizmatters-infra` platform. These requirements form the "Zero Data Loss" contract. Implementation must strictly adhere to the 3-Layer Defense Strategy (GitOps protection, Storage protection, S3 protection).

## 2. Core Requirements

### Requirement CNPG-1: High Availability (The "Self-Healing" Layer)
**Objective:** Withstand node or pod failures without human intervention.
1. THE Cluster SHALL run **3 instances** (1 Primary, 2 Standbys).
2. THE Cluster SHALL use **synchronous replication** (`synchronousCommit: "on"` or `remote_write` depending on latency tolerance) to ensure data exists on at least one standby before committing.
3. THE System SHALL enforce **PodAntiAffinity** to ensure instances run on different nodes.
4. THE System SHALL automatically promote a standby if the primary fails (RTO < 30s).

### Requirement CNPG-2: Point-In-Time Recovery (The "Time Machine" Layer)
**Objective:** Recover from logical corruption (e.g., `DROP TABLE`) to a specific transaction timestamp.
1. THE Cluster SHALL use `barmanObjectStore` for continuous **WAL (Write-Ahead Log) Archiving**.
2. THE Archive Destination SHALL be an S3-compatible bucket.
3. THE WAL files SHALL be compressed (`compression: gzip`) to minimize storage and transfer costs.
4. THE Restore Procedure SHALL support creating a *new* cluster from the backup of an *existing* cluster (Blue/Green recovery).

### Requirement CNPG-3: Backup Lifecycle & Retention
**Objective:** Automate backup cadence and pruning.
1. THE System SHALL perform a full Base Backup every **6 hours** (`0 */6 * * *`).
2. THE System SHALL retain Base Backups and WAL files for **30 days** (`retentionPolicy: "30d"`).
3. THE S3 Credentials SHALL be managed via **External Secrets Operator** (no hardcoded keys).

### Requirement CNPG-4: Triple-Layer Deletion Protection
**Objective:** Prevent data loss from GitOps errors, "fat finger" commands, or ransomware.

*   **Layer 1: GitOps Safety (Crossplane)**
    1. THE Crossplane Managed Resource SHALL have `deletionPolicy: Orphan`.
    2. *Effect:* Deleting the `Claim` in Git removes the Kubernetes resource but leaves the Database running.

*   **Layer 2: Storage Safety (Kubernetes)**
    1. THE Cluster SHALL use a dedicated StorageClass named `postgres-retain`.
    2. THE StorageClass SHALL have `reclaimPolicy: Retain`.
    3. *Effect:* Deleting the PVC/Cluster in Kubernetes leaves the EBS Volume/Disk intact in the cloud provider.

*   **Layer 3: Artifact Safety (S3)**
    1. THE S3 Bucket SHALL have **Versioning** enabled.
    2. THE S3 Bucket SHALL have **Object Lock** enabled (Compliance Mode).
    3. *Effect:* Even if an attacker gains root access, they cannot delete or overwrite backup files until the retention period expires.

### Requirement CNPG-5: Observability
**Objective:** Alert on "Silent Failures" (e.g., WAL archiving stopped working).
1. THE Cluster SHALL have `monitoring.enablePodMonitor: true`.
2. THE System SHALL alert via Robusta/Prometheus on:
    *   `cnpg_wal_archiving_last_success_seconds > 300` (5 mins).
    *   `cnpg_backup_last_status != 'completed'`.

---

## 3. Implementation Reference (Strict Configuration)

The following YAML configurations must be used by the implementation team.

### 3.1 StorageClass Definition
*File: `platform/01-foundation/postgres-storage-class.yaml`*

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: postgres-retain
provisioner: ebs.csi.aws.com # (Or appropriate cloud provisioner)
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain  # <--- CRITICAL: Prevents cloud volume deletion
allowVolumeExpansion: true
```

### 3.2 Composition Spec (Hardcoded Safety)
*File: `platform/04-apis/compositions/postgresql-basic.yaml`*

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: postgresql-basic
spec:
  mode: Pipeline
  pipeline:
    - step: patch-and-transform
      input:
        apiVersion: postgresql.cnpg.io/v1
        kind: Cluster
        spec:
          instances: 3  # Force High Availability
          
          storage:
            size: 20Gi
            storageClass: "postgres-retain" # Force Retain Policy
            
          monitoring:
            enablePodMonitor: true # Enable Metrics
            
          # The Time Machine Configuration
          backup:
            retentionPolicy: "30d"
            barmanObjectStore:
              destinationPath: s3://my-org-postgres-backups/
              endpointURL: https://s3.us-east-1.amazonaws.com
              s3Credentials:
                accessKeyId:
                  name: aws-creds-es
                  key: ACCESS_KEY_ID
                secretAccessKey:
                  name: aws-creds-es
                  key: SECRET_ACCESS_KEY
              wal:
                compression: gzip
            
            # Automated Schedule
            scheduledBackups:
              - name: "frequent-base"
                schedule: "0 */6 * * *" # Every 6 hours
                backupOwnerReference: self
                immediate: true
```

### 3.3 Upgrade Strategy (Blue/Green)

**DO NOT** perform in-place upgrades for major versions.
**DO** use the Blue/Green GitOps flow:

1.  **Commit New Claim:** Create `agent-db-v16.yaml`.
    *   Set `bootstrap.recovery.source: agent-db-v15`.
2.  **Sync:** Wait for data restoration (Time Machine sync).
3.  **Switch:** Update App `Secret` to point to `agent-db-v16-rw`.
4.  **Orphan:** Delete `agent-db-v15.yaml` (Old DB remains running but disconnected).
5.  **Cleanup:** Manually delete old resources only after verification.