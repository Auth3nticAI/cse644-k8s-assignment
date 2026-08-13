#!/usr/bin/env bash
# CSE644 Assignment 02 - install (if needed) and run cloud-provider-kind,
# the standard local stand-in that gives `type: LoadBalancer` Services a
# real, reachable IP on KinD (see README "Requirement 4: LoadBalancer" for
# why this is needed and its Windows/Docker-Desktop networking caveat).
# Installs to ~/.local/bin - no sudo required.
#
# Usage: bash scripts/02-run-cloud-provider-kind.sh
set -euo pipefail
CPK_VERSION="0.11.1"
BIN="$HOME/.local/bin/cloud-provider-kind"

if [ ! -x "$BIN" ]; then
  echo "--- installing cloud-provider-kind v$CPK_VERSION ----------------------"
  mkdir -p "$HOME/.local/bin"
  curl -sSL -o /tmp/cpk.tar.gz \
    "https://github.com/kubernetes-sigs/cloud-provider-kind/releases/download/v${CPK_VERSION}/cloud-provider-kind_${CPK_VERSION}_linux_amd64.tar.gz"
  tar -xzf /tmp/cpk.tar.gz -C /tmp cloud-provider-kind
  mv /tmp/cloud-provider-kind "$BIN"
  chmod +x "$BIN"
else
  echo "cloud-provider-kind already installed at $BIN"
fi

if pgrep -f "$BIN" >/dev/null 2>&1; then
  echo "cloud-provider-kind is already running (pid $(pgrep -f "$BIN"))"
else
  echo "--- starting cloud-provider-kind in the background ---------------------"
  nohup "$BIN" > /tmp/cloud-provider-kind.log 2>&1 &
  disown
  sleep 3
  echo "started, pid $(pgrep -f "$BIN"), logging to /tmp/cloud-provider-kind.log"
fi

echo
echo "Leave this running for the lifetime of the demo. Next: apply k8s/ manifests."
