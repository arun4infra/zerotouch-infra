#!/bin/bash
# Embed Cilium Bootstrap Manifest into Talos Control Plane Config
# This adds the static Cilium manifest to cluster.inlineManifests section
# Only applied to control plane - workers inherit CNI automatically

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CP_CONFIG="$SCRIPT_DIR/../../bootstrap/talos/nodes/cp01-main/config.yaml"
CILIUM_MANIFEST="$SCRIPT_DIR/../../bootstrap/talos-templates/cilium-bootstrap.yaml"

# Check if Cilium manifest exists
if [ ! -f "$CILIUM_MANIFEST" ]; then
    echo "ERROR: Cilium bootstrap manifest not found at: $CILIUM_MANIFEST"
    exit 1
fi

# Check if control plane config exists
if [ ! -f "$CP_CONFIG" ]; then
    echo "ERROR: Control plane config not found at: $CP_CONFIG"
    exit 1
fi

echo "Embedding Cilium manifest into control plane Talos config..."

# Check if inlineManifests already exists (uncommented)
if grep -q "^[[:space:]]*inlineManifests:" "$CP_CONFIG"; then
    echo "✓ inlineManifests section already exists - skipping"
    exit 0
fi

# Find insertion point (after allowSchedulingOnControlPlanes)
LINE_NUM=$(grep -n "allowSchedulingOnControlPlanes:" "$CP_CONFIG" | cut -d: -f1)

if [ -z "$LINE_NUM" ]; then
    echo "ERROR: Could not find insertion point in control plane config"
    exit 1
fi

INSERT_LINE=$((LINE_NUM + 1))

# Create inline manifest section
cat > /tmp/inline-manifest.yaml <<'EOF'
    # Cilium CNI for bootstrap - minimal config
    # ArgoCD will adopt and enable full features (Hubble, Gateway API)
    inlineManifests:
        - name: cilium-bootstrap
          contents: |
EOF

# Add Cilium manifest content with proper indentation (12 spaces)
sed 's/^/            /' "$CILIUM_MANIFEST" >> /tmp/inline-manifest.yaml

# Backup original
cp "$CP_CONFIG" "$CP_CONFIG.backup-$(date +%Y%m%d-%H%M%S)"

# Insert into config
{
    head -n "$LINE_NUM" "$CP_CONFIG"
    cat /tmp/inline-manifest.yaml
    tail -n +$((INSERT_LINE)) "$CP_CONFIG"
} > /tmp/cp-config-new.yaml

# Replace with new config
mv /tmp/cp-config-new.yaml "$CP_CONFIG"
rm /tmp/inline-manifest.yaml

echo "✓ Cilium manifest embedded in control plane config"
echo "  Backup created: $CP_CONFIG.backup-*"
echo "  Workers will inherit CNI automatically"
