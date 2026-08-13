#!/usr/bin/env bash
# CSE644 Assignment 02 - a single holistic snapshot of everything running,
# for a grader to sanity-check the whole platform at a glance.
#
# Usage: bash scripts/98-final-state-snapshot.sh
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$REPO_ROOT/evidence/logs/98-final-state-snapshot.txt"
mkdir -p "$(dirname "$LOG")"
export PATH="$HOME/.local/bin:$PATH"

{
  echo "==================================================================="
  echo " Final cluster state snapshot"
  echo " Captured: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "==================================================================="

  echo
  echo "--- kubectl get nodes -----------------------------------------------"
  kubectl get nodes -o wide

  echo
  echo "--- kubectl get all -n cse644 ----------------------------------------"
  kubectl -n cse644 get all -o wide

  echo
  echo "--- kubectl get configmap,secret,pvc -n cse644 ------------------------"
  kubectl -n cse644 get configmap,secret,pvc

  echo
  echo "--- kubectl get ingress -n cse644 --------------------------------------"
  kubectl -n cse644 get ingress -o wide

  echo
  echo "--- kubectl get pods -n ingress-nginx ----------------------------------"
  kubectl -n ingress-nginx get pods -o wide

  echo
  echo "--- images loaded into the KinD cluster --------------------------------"
  docker exec cse644-control-plane crictl images 2>/dev/null | grep -E "cse644|IMAGE"
} > "$LOG" 2>&1

echo "Snapshot ($(wc -l < "$LOG") lines) -> $LOG"
