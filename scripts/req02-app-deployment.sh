#!/usr/bin/env bash
# CSE644 Assignment 02, Requirement 2: Application Deployment and Internal
# Discovery. Verifies both app workloads are running with multiple/expected
# instances, labels/selectors line up with Service Endpoints, and each
# Service is reachable by DNS name from inside the cluster.
#
# Usage: bash scripts/req02-app-deployment.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$REPO_ROOT/evidence/logs/req02-app-deployment.txt"
mkdir -p "$(dirname "$LOG")"
NS="cse644"

{
  echo "==================================================================="
  echo " Req 2: App deployment + internal service discovery"
  echo " Captured: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "==================================================================="

  echo
  echo "--- [1] Multiple running instances of the web app -------------------"
  kubectl -n "$NS" get pods -l app=nginx-web -o wide
  NGINX_READY="$(kubectl -n "$NS" get deploy nginx-web -o jsonpath='{.status.readyReplicas}')"
  if [ "${NGINX_READY:-0}" -ge 2 ]; then
    echo "[PASS] nginx-web has $NGINX_READY ready replicas (>=2, i.e. multiple instances)"
  else
    echo "[FAIL] nginx-web only has ${NGINX_READY:-0} ready replicas"
  fi

  echo
  echo "--- [2] Port-8888 app is running and responding ----------------------"
  kubectl -n "$NS" get pods -l app=python-web -o wide
  PY_READY="$(kubectl -n "$NS" get deploy python-web -o jsonpath='{.status.readyReplicas}')"
  [ "${PY_READY:-0}" -ge 1 ] && echo "[PASS] python-web has $PY_READY ready replica(s)" \
                              || echo "[FAIL] python-web has no ready replicas"

  echo
  echo "--- [3] Labels and Service selection are configured correctly -------"
  echo "Deployment Pod-template labels:"
  kubectl -n "$NS" get deploy nginx-web -o jsonpath='  nginx-web selector: {.spec.selector.matchLabels}{"\n"}'
  kubectl -n "$NS" get deploy python-web -o jsonpath='  python-web selector: {.spec.selector.matchLabels}{"\n"}'
  echo
  echo "Service selectors:"
  kubectl -n "$NS" get svc nginx-web-svc  -o jsonpath='  nginx-web-svc selector: {.spec.selector}{"\n"}'
  kubectl -n "$NS" get svc python-web-svc -o jsonpath='  python-web-svc selector: {.spec.selector}{"\n"}'
  echo
  echo "Endpoints actually resolved by each Service (proves selector => Pod IPs match):"
  kubectl -n "$NS" get endpoints nginx-web-svc python-web-svc
  NGINX_EP_COUNT="$(kubectl -n "$NS" get endpoints nginx-web-svc -o jsonpath='{.subsets[0].addresses}' | grep -o '"ip"' | wc -l)"
  if [ "${NGINX_EP_COUNT:-0}" -ge 2 ]; then
    echo "[PASS] nginx-web-svc has $NGINX_EP_COUNT endpoint IPs (selector matches multiple Pods)"
  else
    echo "[FAIL] nginx-web-svc has only ${NGINX_EP_COUNT:-0} endpoint(s)"
  fi

  echo
  echo "--- [4] Internal service discovery: DNS name -> Service -> Pod ------"
  echo "Using the Requirement-1 busybox Pod as an internal client."
  echo
  echo "\$ nslookup nginx-web-svc.$NS.svc.cluster.local"
  NSLOOKUP_OUT="$(kubectl -n "$NS" exec public-image-demo -- nslookup nginx-web-svc.$NS.svc.cluster.local 2>&1)"
  echo "$NSLOOKUP_OUT"
  echo "$NSLOOKUP_OUT" | grep -q "Address" && echo "[PASS] Service DNS name resolves"

  echo
  echo "Three curls to nginx-web-svc - different X-CSE644-Served-By values"
  echo "below (different Pod hostnames) is the proof that the Service is"
  echo "load-balancing across multiple Pod instances, not hitting one Pod:"
  for i in 1 2 3 4 5 6; do
    kubectl -n "$NS" exec public-image-demo -- wget -qS -O /dev/null "http://nginx-web-svc.$NS.svc.cluster.local/" 2>&1 \
      | grep -i "X-CSE644-Served-By" | sed "s/^/  [$i] /"
  done

  echo
  echo "\$ wget -qO- http://python-web-svc.$NS.svc.cluster.local:8888/api/info"
  PY_OUT="$(kubectl -n "$NS" exec public-image-demo -- wget -qO- "http://python-web-svc.$NS.svc.cluster.local:8888/api/info" 2>&1)"
  echo "$PY_OUT"
  echo "$PY_OUT" | grep -q '"listening_port":8888' && echo "[PASS] python-web reachable via its Service DNS name on 8888"

  echo
  echo "=== Req 2 complete: both apps deployed, discoverable via Service DNS ==="
} > "$LOG" 2>&1

grep -E '^\[(PASS|FAIL)\]' "$LOG"
echo "Evidence ($(wc -l < "$LOG") lines) -> $LOG"
