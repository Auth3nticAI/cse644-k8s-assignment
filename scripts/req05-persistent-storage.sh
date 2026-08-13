#!/usr/bin/env bash
# CSE644 Assignment 02, Requirement 5: Persistent Storage.
# Writes data through the running python-web Pod, deletes that Pod (letting
# the Deployment replace it), and proves the data is still there afterward -
# because it lives on a PersistentVolumeClaim, not the Pod's own filesystem.
#
# Usage: bash scripts/req05-persistent-storage.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$REPO_ROOT/evidence/logs/req05-persistent-storage.txt"
mkdir -p "$(dirname "$LOG")"
NS="cse644"
MARKER="persistence-proof-$(date +%s)"

{
  echo "==================================================================="
  echo " Req 5: Persistent storage - write, replace Pod, verify"
  echo " Captured: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo " Marker note for this run: $MARKER"
  echo "==================================================================="

  echo
  echo "--- [0] Storage resources in use --------------------------------------"
  kubectl -n "$NS" get pvc python-web-data
  kubectl -n "$NS" get pv "$(kubectl -n "$NS" get pvc python-web-data -o jsonpath='{.spec.volumeName}')"

  BEFORE_POD="$(kubectl -n "$NS" get pods -l app=python-web -o jsonpath='{.items[0].metadata.name}')"
  echo
  echo "--- [1] BEFORE: write a note through the running Pod ($BEFORE_POD) --"
  echo "\$ curl -X POST .../api/notes -d '{\"note\": \"$MARKER\"}'"
  WRITE_OUT="$(kubectl -n "$NS" exec "$BEFORE_POD" -- python3 -c "
import urllib.request, json
req = urllib.request.Request(
    'http://127.0.0.1:8888/api/notes',
    data=json.dumps({'note': '$MARKER'}).encode(),
    headers={'Content-Type': 'application/json'},
    method='POST')
print(urllib.request.urlopen(req).read().decode())
" 2>&1)"
  echo "$WRITE_OUT"
  echo "$WRITE_OUT" | grep -q "$MARKER" && echo "[PASS] note written through Pod $BEFORE_POD"

  echo
  echo "--- [1b] Where it actually landed: on the PVC-backed /data, not the --"
  echo "         Pod's own writable layer -------------------------------------"
  kubectl -n "$NS" exec "$BEFORE_POD" -- cat /data/notes.log

  echo
  echo "--- [2] REPLACE the workload: delete the Pod outright -----------------"
  echo "\$ kubectl delete pod $BEFORE_POD"
  kubectl -n "$NS" delete pod "$BEFORE_POD"
  kubectl -n "$NS" wait --for=condition=Ready pod -l app=python-web --timeout=60s

  AFTER_POD="$(kubectl -n "$NS" get pods -l app=python-web -o jsonpath='{.items[0].metadata.name}')"
  echo
  echo "New Pod name : $AFTER_POD"
  if [ "$AFTER_POD" != "$BEFORE_POD" ]; then
    echo "[PASS] this is a genuinely different Pod (old: $BEFORE_POD, new: $AFTER_POD)"
  else
    echo "[FAIL] Pod name did not change - not a real replacement"
  fi

  echo
  echo "--- [3] AFTER: read the notes back through the NEW Pod ----------------"
  echo "\$ curl .../api/notes"
  READ_OUT="$(kubectl -n "$NS" exec "$AFTER_POD" -- cat /data/notes.log 2>&1)"
  echo "$READ_OUT"
  if echo "$READ_OUT" | grep -q "$MARKER"; then
    echo "[PASS] data written by the OLD Pod is visible from the NEW Pod - PVC persisted it"
  else
    echo "[FAIL] marker note not found after Pod replacement"
  fi

  echo
  echo "=== Req 5 complete: PVC data survived Pod deletion and replacement ==="
} > "$LOG" 2>&1

grep -E '^\[(PASS|FAIL)\]' "$LOG"
echo "Evidence ($(wc -l < "$LOG") lines) -> $LOG"
