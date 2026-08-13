#!/usr/bin/env bash
# CSE644 Assignment 02 - build the three application images locally and load
# them straight into the KinD cluster's node containerd, bypassing any
# registry (this is the "local-image loading approach" the assignment asks
# to have documented - see README "Local image loading").
#
# Usage: bash scripts/01-build-and-load-images.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

IMAGES=(
  "auth3nticai/cse644-k8s-nginx:v1:apps/nginx-web"
  "auth3nticai/cse644-k8s-python:v1:apps/python-web"
  "auth3nticai/cse644-k8s-haproxy:v1:apps/haproxy"
)

for entry in "${IMAGES[@]}"; do
  IFS=':' read -r name tag ctx <<< "$entry"
  image="${name}:${tag}"
  echo "--- building $image -----------------------------------------------"
  docker build --build-arg BUILD_DATE="$BUILD_DATE" -t "$image" "$REPO_ROOT/$ctx"
done

echo
echo "--- loading images into the 'cse644' KinD cluster ---------------------"
kind load docker-image \
  auth3nticai/cse644-k8s-nginx:v1 \
  auth3nticai/cse644-k8s-python:v1 \
  auth3nticai/cse644-k8s-haproxy:v1 \
  --name cse644

echo
echo "Images built and loaded. Next: scripts/02-run-cloud-provider-kind.sh"
