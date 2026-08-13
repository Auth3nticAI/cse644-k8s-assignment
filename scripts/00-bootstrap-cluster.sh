#!/usr/bin/env bash
# CSE644 Assignment 02 - one-time environment setup.
# Creates the KinD cluster and installs the ingress-nginx controller.
# Idempotent: safe to re-run (kind/kubectl no-op on things that already exist).
#
# Usage: bash scripts/00-bootstrap-cluster.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"

echo "--- kind create cluster (name: cse644) -------------------------------"
if kind get clusters 2>/dev/null | grep -qx cse644; then
  echo "cluster 'cse644' already exists, skipping create"
else
  kind create cluster --config "$REPO_ROOT/kind/kind-config.yaml"
fi

echo
echo "--- wait for nodes Ready ----------------------------------------------"
kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo
echo "--- install ingress-nginx controller (pinned controller-v1.15.1) -----"
kubectl apply -f "$REPO_ROOT/k8s/vendor/ingress-nginx-kind-controller-v1.15.1.yaml"
kubectl -n ingress-nginx wait --for=condition=Ready pod \
  -l app.kubernetes.io/component=controller --timeout=180s

echo
echo "Cluster ready. Next: scripts/01-build-and-load-images.sh"
