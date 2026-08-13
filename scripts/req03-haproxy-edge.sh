#!/usr/bin/env bash
# CSE644 Assignment 02, Requirement 3: HAProxy edge component.
# Proves HAProxy reaches nginx-web only through nginx-web-svc's Kubernetes
# Service DNS name (never a Pod IP), and captures a successful proxied
# request plus HAProxy's own backend health view.
#
# Usage: bash scripts/req03-haproxy-edge.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$REPO_ROOT/evidence/logs/req03-haproxy-edge.txt"
mkdir -p "$(dirname "$LOG")"
NS="cse644"

{
  echo "==================================================================="
  echo " Req 3: HAProxy edge component in front of nginx-web"
  echo " Captured: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "==================================================================="

  echo
  echo "--- [1] The backend line in haproxy.cfg targets a Service, not a Pod -"
  grep -n "server nginx-web" "$REPO_ROOT/apps/haproxy/haproxy.cfg"
  if grep -q "server nginx-web nginx-web-svc.cse644.svc.cluster.local" "$REPO_ROOT/apps/haproxy/haproxy.cfg"; then
    echo "[PASS] backend target is the Service DNS name, not a Pod IP/name"
  else
    echo "[FAIL] backend target does not reference the Service DNS name"
  fi

  echo
  echo "--- [2] HAProxy Pod is running, nginx-web-svc has multiple endpoints -"
  kubectl -n "$NS" get pods -l app=haproxy-edge -o wide
  kubectl -n "$NS" get endpoints nginx-web-svc

  echo
  echo "--- [3] HAProxy's own view of the backend (via its runtime resolver) -"
  HAPROXY_POD="$(kubectl -n "$NS" get pods -l app=haproxy-edge -o jsonpath='{.items[0].metadata.name}')"
  kubectl -n "$NS" exec "$HAPROXY_POD" -- sh -c "echo 'show servers state' | socat stdio /var/run/haproxy.sock 2>/dev/null || true"
  echo "(stats page HTML also served at :8404/ inside the cluster - see curl below)"

  echo
  echo "--- [4] SUCCESSFUL PROXIED REQUEST from inside the cluster ----------"
  echo "Using the Requirement-1 busybox Pod as the client, hitting HAProxy's"
  echo "Service (haproxy-edge-svc), which forwards to nginx-web-svc:"
  echo
  for i in 1 2 3 4; do
    echo "[$i] \$ wget -qS -O- http://haproxy-edge-svc.$NS.svc.cluster.local/"
    OUT="$(kubectl -n "$NS" exec public-image-demo -- wget -qS -O- "http://haproxy-edge-svc.$NS.svc.cluster.local/" 2>&1)"
    echo "$OUT" | grep -iE "HTTP/|X-CSE644-Proxy|X-CSE644-Served-By" | sed 's/^/    /'
    echo
  done

  FINAL="$(kubectl -n "$NS" exec public-image-demo -- wget -qS -O- "http://haproxy-edge-svc.$NS.svc.cluster.local/" 2>&1)"
  if echo "$FINAL" | grep -qi "X-CSE644-Proxy: haproxy" && echo "$FINAL" | grep -qi "X-CSE644-Served-By"; then
    echo "[PASS] Request passed through HAProxy (X-CSE644-Proxy header) and reached an nginx-web Pod (Served-By header)"
  else
    echo "[FAIL] Expected proxy/served-by headers not both present"
  fi

  echo
  echo "=== Req 3 complete: HAProxy reaches nginx-web via Service discovery ==="
} > "$LOG" 2>&1

grep -E '^\[(PASS|FAIL)\]' "$LOG"
echo "Evidence ($(wc -l < "$LOG") lines) -> $LOG"
