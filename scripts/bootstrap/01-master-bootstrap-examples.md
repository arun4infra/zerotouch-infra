# Single node cluster
./scripts/bootstrap/01-master-bootstrap.sh 46.62.218.181 'gmdpnHi9qCJb'

# Multi-node cluster with worker node (same password for both nodes)
./scripts/bootstrap/01-master-bootstrap.sh 46.62.218.181 'gmdpnHi9qCJb' --worker-nodes worker01:95.216.151.243

# Multi-node cluster with worker node (different passwords)
./scripts/bootstrap/01-master-bootstrap.sh 46.62.218.181 'ControlPlanePassword' --worker-nodes worker01:95.216.151.243 --worker-password 'WorkerNodePassword'

# Multi-node cluster with multiple workers
./scripts/bootstrap/01-master-bootstrap.sh 46.62.218.181 'gmdpnHi9qCJb' --worker-nodes worker01:95.216.151.243,worker02:95.216.151.244
