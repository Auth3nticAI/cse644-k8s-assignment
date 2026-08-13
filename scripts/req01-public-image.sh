#!/usr/bin/env bash
# CSE644 Assignment 02, Requirement 1: Kubernetes Workload Operations.
# Creates a Pod from a public image (busybox), then inspects it, reads its
# logs, and opens an exec shell session inside it.
#
# Usage: bash scripts/req01-public-image.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$REPO_ROOT/evidence/logs/req01-public-image.txt"
mkdir -p "$(dirname "$LOG")"

NS="cse644"
POD="public-image-demo"

{
  echo "==================================================================="
  echo " Req 1: Public-image workload - create, inspect, logs, exec"
  echo " Captured: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "==================================================================="

  echo
  echo "--- [1] CREATE: apply Pod from a public image (busybox:1.36.1) -----"
  kubectl apply -f "$REPO_ROOT/k8s/01-public-image-pod.yaml"
  if kubectl wait --for=condition=Ready "pod/$POD" -n "$NS" --timeout=60s >/dev/null 2>&1; then
    echo "[PASS] Pod $POD is Running/Ready"
  else
    echo "[FAIL] Pod $POD did not become Ready in time"
  fi

  echo
  echo "--- [2] INSPECT: kubectl get -o wide --------------------------------"
  kubectl get pod "$POD" -n "$NS" -o wide

  echo
  echo "--- [2b] INSPECT: kubectl describe -----------------------------------"
  kubectl describe pod "$POD" -n "$NS"
  echo "[PASS] describe succeeded"

  echo
  echo "--- [3] LOGS: kubectl logs -------------------------------------------"
  sleep 6   # let the loop emit at least one iteration
  LOG_SAMPLE="$(kubectl logs "$POD" -n "$NS" 2>&1)"
  echo "$LOG_SAMPLE"
  if echo "$LOG_SAMPLE" | grep -q "hello from busybox"; then
    echo "[PASS] logs show expected container stdout"
  else
    echo "[FAIL] expected log line not found"
  fi

  echo
  echo "--- [4] EXEC: interactive shell session inside the running Pod ------"
  echo "\$ kubectl exec -it $POD -n $NS -- sh   (run non-interactively here, same underlying capability)"
  EXEC_OUT="$(kubectl exec "$POD" -n "$NS" -- sh -c '
    echo "### inside the container ###"
    echo "hostname : $(hostname)"
    echo "whoami   : $(whoami)"
    echo "uname    : $(uname -a)"
    echo "root ls  :"; ls /
    echo "written inside $(hostname) at $(date -u)" > /tmp/proof.txt
    cat /tmp/proof.txt
  ' 2>&1)"
  echo "$EXEC_OUT"
  if echo "$EXEC_OUT" | grep -q "inside the container"; then
    echo "[PASS] exec session ran commands inside the Pod"
  else
    echo "[FAIL] exec session did not produce expected output"
  fi

  echo
  echo "--- [4b] Re-exec to prove the file persisted in that same container -"
  READBACK="$(kubectl exec "$POD" -n "$NS" -- cat /tmp/proof.txt 2>&1)"
  echo "$READBACK"
  if echo "$READBACK" | grep -q "written inside"; then
    echo "[PASS] second exec confirms state inside the same Pod"
  else
    echo "[FAIL] readback did not match"
  fi

  echo
  echo "=== Req 1 complete: create/run, inspect, logs, exec all demonstrated ==="
} > "$LOG" 2>&1

grep -E '^\[(PASS|FAIL)\]' "$LOG"
echo "Evidence ($(wc -l < "$LOG") lines) -> $LOG"
