#!/usr/bin/env bash
# CSE644 Assignment 02 - full teardown: stop cloud-provider-kind, delete the
# KinD cluster (which removes every Deployment/Service/PVC/etc. with it),
# and remove the locally built images.
#
# Usage: bash scripts/99-cleanup.sh
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"

echo "--- stopping cloud-provider-kind ---------------------------------------"
pkill -f "$HOME/.local/bin/cloud-provider-kind" 2>/dev/null && echo "stopped" || echo "was not running"
# Any LB proxy containers it created (kindccm-*) are removed with the
# cluster below since they're attached to the 'kind' Docker network, but
# clean them up explicitly in case cloud-provider-kind was already dead:
docker ps -aq --filter "label=io.x-k8s.cloud-provider-kind.cluster=cse644" | xargs -r docker rm -f

echo
echo "--- deleting the KinD cluster -------------------------------------------"
kind delete cluster --name cse644

echo
echo "--- removing locally built images ---------------------------------------"
docker rmi -f \
  auth3nticai/cse644-k8s-nginx:v1 \
  auth3nticai/cse644-k8s-python:v1 \
  auth3nticai/cse644-k8s-haproxy:v1 2>/dev/null || true

echo
echo "Cleanup complete."
