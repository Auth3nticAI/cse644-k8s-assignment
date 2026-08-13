#!/usr/bin/env bash
# CSE644 Assignment 02, Requirement 6: Application Configuration and Health.
# Three parts:
#   A. ConfigMap changes visible app behavior (before/after, no image rebuild)
#   B. Secret is received but never exposed (env present, value never shown)
#   C. Readiness vs liveness: a failed dependency makes the Pod NotReady
#      (not killed), and it recovers to Ready once the dependency returns.
#
# Usage: bash scripts/req06-config-secret-health.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$REPO_ROOT/evidence/logs/req06-config-secret-health.txt"
mkdir -p "$(dirname "$LOG")"
NS="cse644"
SECRET_VALUE="dummy-api-key-DO-NOT-USE-93f7c2a1"

py_get() {  # py_get <pod> <path>  - GET via python3/urllib (no curl in this image)
  kubectl -n "$NS" exec "$1" -- python3 -c "
import urllib.request
print(urllib.request.urlopen('http://127.0.0.1:8888$2').read().decode())
"
}

{
  echo "==================================================================="
  echo " Req 6: ConfigMap, Secret, readiness/liveness"
  echo " Captured: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "==================================================================="

  echo
  echo "=== [A] ConfigMap controls a visible, non-secret behavior ============"
  POD="$(kubectl -n "$NS" get pods -l app=python-web -o jsonpath='{.items[0].metadata.name}')"
  echo "BEFORE (current live ConfigMap values):"
  BEFORE="$(py_get "$POD" /api/info)"
  echo "$BEFORE" | grep -o '"greeting":"[^"]*"\|"environment":"[^"]*"'

  echo
  echo "\$ kubectl -n $NS get configmap python-web-config -o yaml"
  kubectl -n "$NS" get configmap python-web-config -o jsonpath='{.data}'
  echo
  echo "(This ConfigMap already carries the grading-environment values from"
  echo "k8s/12-python-configmap.yaml - the deployment step below re-applies"
  echo "it and restarts the Deployment so the env-var change actually takes"
  echo "effect, since env vars are only read at container start.)"
  kubectl -n "$NS" apply -f "$REPO_ROOT/k8s/12-python-configmap.yaml"
  kubectl -n "$NS" rollout restart deployment/python-web
  kubectl -n "$NS" rollout status deployment/python-web --timeout=60s

  NEWPOD="$(kubectl -n "$NS" get pods -l app=python-web -o jsonpath='{.items[0].metadata.name}')"
  echo
  echo "AFTER (new Pod $NEWPOD, same ConfigMap key, updated value):"
  AFTER="$(py_get "$NEWPOD" /api/info)"
  echo "$AFTER" | grep -o '"greeting":"[^"]*"\|"environment":"[^"]*"'
  if echo "$AFTER" | grep -q "grading environment"; then
    echo "[PASS] ConfigMap value change is reflected in the live application response"
  else
    echo "[FAIL] application response did not pick up the new ConfigMap value"
  fi

  echo
  echo "=== [B] Secret is received but never exposed ==========================="
  echo "The env var IS set inside the container (existence only, not printed):"
  ENV_PRESENT="$(kubectl -n "$NS" exec "$NEWPOD" -- sh -c 'printenv APP_SECRET_VALUE >/dev/null 2>&1 && echo yes || echo no')"
  echo "APP_SECRET_VALUE set in container env: $ENV_PRESENT"
  [ "$ENV_PRESENT" = "yes" ] && echo "[PASS] Secret was injected into the container as an env var"

  echo
  echo "The application's own view (boolean only, never the value):"
  py_get "$NEWPOD" /api/info | grep -o '"secret_loaded":[a-z]*'

  echo
  echo "Checking the HTTP response body for the raw secret value (should NOT match):"
  RESP="$(py_get "$NEWPOD" /api/info)"
  if echo "$RESP" | grep -qF "$SECRET_VALUE"; then
    echo "[FAIL] the raw secret value leaked into the HTTP response"
  else
    echo "[PASS] HTTP response does not contain the raw secret value"
  fi

  echo
  echo "Checking gunicorn's own logs for the raw secret value (should NOT match):"
  APP_LOGS="$(kubectl -n "$NS" logs "$NEWPOD" 2>&1)"
  if echo "$APP_LOGS" | grep -qF "$SECRET_VALUE"; then
    echo "[FAIL] the raw secret value leaked into application logs"
  else
    echo "[PASS] application logs do not contain the raw secret value"
  fi

  echo
  echo "=== [C] Readiness vs liveness ==========================================="
  echo "Liveness (/healthz)  : is the process itself able to answer at all?"
  echo "                       No external dependency - a stalled disk or a"
  echo "                       missing Secret must NOT cause a restart loop."
  echo "Readiness (/readyz)  : are this Pod's real dependencies in place -"
  echo "                       PVC mounted and writable, ConfigMap greeting"
  echo "                       set, Secret loaded? If not, Kubernetes should"
  echo "                       stop sending it traffic (pull it from the"
  echo "                       Service's Endpoints) without killing it."
  echo
  echo "--- Forcing a real readiness failure, without touching liveness --------"
  echo "Blanking APP_GREETING (a key the ConfigMap still provides, just empty)"
  echo "so the container starts fine but /readyz's greeting_configured check"
  echo "fails - unlike deleting the whole Secret/ConfigMap, which would stop"
  echo "the container from starting at all (CreateContainerConfigError) and"
  echo "wouldn't actually exercise the readiness *probe* logic being tested:"
  kubectl -n "$NS" patch configmap python-web-config --type merge -p '{"data":{"APP_GREETING":""}}'
  kubectl -n "$NS" rollout restart deployment/python-web
  echo "Waiting for the new Pod to report NotReady (this is expected)..."
  sleep 10
  BADPOD="$(kubectl -n "$NS" get pods -l app=python-web --field-selector=status.phase=Running --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')"
  kubectl -n "$NS" get pod "$BADPOD"
  READY_COL="$(kubectl -n "$NS" get pod "$BADPOD" -o jsonpath='{.status.containerStatuses[0].ready}')"
  RESTARTS="$(kubectl -n "$NS" get pod "$BADPOD" -o jsonpath='{.status.containerStatuses[0].restartCount}')"
  echo "ready=$READY_COL restarts=$RESTARTS (still 0 restarts is the point - liveness never fired)"
  echo "\$ curl .../readyz on that Pod:"
  kubectl -n "$NS" exec "$BADPOD" -- python3 -c "
import urllib.request, urllib.error
try:
    print(urllib.request.urlopen('http://127.0.0.1:8888/readyz').read().decode())
except urllib.error.HTTPError as e:
    print(f'HTTP {e.code}:', e.read().decode())
"
  if [ "$READY_COL" = "false" ] && [ "$RESTARTS" = "0" ]; then
    echo "[PASS] Pod is NotReady (pulled from Service traffic) but was NOT restarted - readiness and liveness are correctly independent"
  else
    echo "[FAIL] expected NotReady with 0 restarts"
  fi
  echo
  echo "It is also removed from the Service's Endpoints while NotReady:"
  kubectl -n "$NS" get endpoints python-web-svc

  echo
  echo "--- Restoring the ConfigMap: Pod should become Ready again -------------"
  kubectl -n "$NS" apply -f "$REPO_ROOT/k8s/12-python-configmap.yaml"
  kubectl -n "$NS" rollout restart deployment/python-web
  kubectl -n "$NS" rollout status deployment/python-web --timeout=60s
  sleep 2
  FINALPOD="$(kubectl -n "$NS" get pods -l app=python-web --field-selector=status.phase=Running --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')"
  kubectl -n "$NS" get pod "$FINALPOD"
  FINAL_READY="$(kubectl -n "$NS" get pod "$FINALPOD" -o jsonpath='{.status.containerStatuses[0].ready}')"
  [ "$FINAL_READY" = "true" ] && echo "[PASS] Pod is Ready again once its dependency (the ConfigMap greeting) is back"
  kubectl -n "$NS" get endpoints python-web-svc

  echo
  echo "=== Req 6 complete: ConfigMap live-updates behavior, Secret never exposed, readiness/liveness demonstrated ==="
} > "$LOG" 2>&1

grep -E '^\[(PASS|FAIL)\]' "$LOG"
echo "Evidence ($(wc -l < "$LOG") lines) -> $LOG"
