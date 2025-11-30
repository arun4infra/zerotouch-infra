- Confirm CNPG version and validate scheduledBackups and barmanObjectStore field names.
	•	Composition enforces instances: 3, storageClassName: postgres-retain, and backup.* fields.
	•	For any provider-managed resources created via Composition, set spec.deletionPolicy: Orphan.
	•	Create postgres-retain StorageClass with reclaimPolicy: Retain.
	•	Create S3 bucket with:
	•	Versioning = ON
	•	Object Lock = Enabled (Compliance/Governance as policy requires) at creation time
	•	SSE-KMS enabled
	•	Lifecycle + transition rules for older backups (Glacier/IA) if cost matters
	•	Use IRSA / short-lived creds; if not possible, store creds in ESO and rotate automatically.
	•	Configure Prometheus/Robusta alerts:
	•	cnpg_wal_archiving_last_success_seconds > 300
	•	cnpg_backup_last_status != "completed"
	•	WAL lag / replica lag > threshold
	•	Implement monthly restore test: restore to temp cluster and run smoke tests.
	•	Document runbook for:
	•	Recovery to timestamp T
	•	Blue/Green upgrade workflow
	•	Manual PV orphaning and volume attach/detach steps
	•	Add CI lint/validation to ensure backup.* is present in Composition (prevent developer override)