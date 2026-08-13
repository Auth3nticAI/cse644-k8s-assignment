#!/usr/bin/env bash
# CSE644 Assignment 02 - apply every application manifest in order.
# (The ingress-nginx controller in k8s/vendor/ is applied separately by
# scripts/00-bootstrap-cluster.sh, before this.)
#
# Usage: bash scripts/03-apply-all-manifests.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"

for f in "$REPO_ROOT"/k8s/[0-9]*.yaml; do
  echo "--- kubectl apply -f $(basename "$f") ---"
  kubectl apply -f "$f"
done

echo
echo "--- waiting for rollouts ------------------------------------------------"
kubectl -n cse644 rollout status deployment/nginx-web --timeout=120s
kubectl -n cse644 rollout status deployment/python-web --timeout=120s
kubectl -n cse644 rollout status deployment/haproxy-edge --timeout=120s

echo
echo "All manifests applied. Run scripts/req0*.sh to (re)generate evidence."
