#!/bin/bash
# Bootstrap script to inject AWS credentials for ESO
# Usage: ./inject-secrets.sh <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY>

set -e

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <AWS_ACCESS_KEY_ID> <AWS_SECRET_ACCESS_KEY>"
    exit 1
fi

AWS_ACCESS_KEY_ID=$1
AWS_SECRET_ACCESS_KEY=$2

echo "Creating aws-access-token secret in external-secrets namespace..."
kubectl create secret generic aws-access-token \
  --namespace external-secrets \
  --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ AWS credentials injected successfully"
echo "ESO can now authenticate to AWS Systems Manager Parameter Store"
