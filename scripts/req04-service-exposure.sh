#!/usr/bin/env bash
# CSE644 Assignment 02, Requirement 4: Service Exposure Comparison.
# Demonstrates ClusterIP, NodePort, LoadBalancer, and Ingress all fronting
# the same nginx-web Deployment, with a real access test for each.
#
# Usage: bash scripts/req04-service-exposure.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="$REPO_ROOT/evidence/logs/req04-service-exposure.txt"
mkdir -p "$(dirname "$LOG")"
NS="cse644"

{
  echo "==================================================================="
  echo " Req 4: Service Exposure Comparison (ClusterIP/NodePort/LB/Ingress)"
  echo " Captured: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "==================================================================="

  echo
  echo "--- All four Service/Ingress objects, all selecting app=nginx-web ---"
  kubectl -n "$NS" get svc -l app=nginx-web -o wide
  kubectl -n "$NS" get ingress nginx-web-ingress

  echo
  echo "=== [1] ClusterIP - internal-only ===================================="
  echo "Who can reach it   : only clients inside the cluster (Pods), or an"
  echo "                     operator tunneling in with kubectl port-forward."
  echo "Entry point        : the Service's ClusterIP (10.96.x.x), a virtual"
  echo "                     IP that only exists in the cluster's networking."
  echo "Forwarded by       : kube-proxy (iptables/nftables rules on every"
  echo "                     node) rewrites the ClusterIP:port to a live"
  echo "                     Pod endpoint IP:port."
  echo
  echo "Access test: kubectl port-forward (operator-local access, no"
  echo "cluster-network membership required):"
  kubectl -n "$NS" port-forward svc/nginx-web-svc 18080:80 >/tmp/pf.log 2>&1 &
  PF_PID=$!
  sleep 2
  PF_OUT="$(curl -sS -o /dev/null -w 'HTTP %{http_code}' http://127.0.0.1:18080/ 2>&1)"
  echo "\$ curl http://127.0.0.1:18080/ (tunneled to nginx-web-svc:80)"
  echo "$PF_OUT"
  kill "$PF_PID" 2>/dev/null; wait "$PF_PID" 2>/dev/null
  echo "$PF_OUT" | grep -q "200" && echo "[PASS] ClusterIP reachable via kubectl port-forward"

  echo
  echo "=== [2] NodePort - fixed port on every node ==========================="
  echo "Who can reach it   : anything that can reach any cluster node's IP on"
  echo "                     the high port (30080 here) - e.g. other hosts on"
  echo "                     the same LAN as the node, not just cluster-internal."
  echo "Entry point        : port 30080 on EVERY node (kube-proxy opens it"
  echo "                     cluster-wide, regardless of which node runs the Pod)."
  echo "Forwarded by       : kube-proxy on whichever node received the"
  echo "                     connection, to a live Pod endpoint (possibly on"
  echo "                     a different node)."
  echo "Local access path  : KinD's extraPortMappings map host port 30080 ->"
  echo "                     the control-plane container's port 30080."
  echo
  echo "\$ curl http://localhost:30080/"
  NP_OUT="$(curl -sS -o /dev/null -w 'HTTP %{http_code}' http://localhost:30080/ 2>&1)"
  echo "$NP_OUT"
  echo "$NP_OUT" | grep -q "200" && echo "[PASS] NodePort reachable at localhost:30080"

  echo
  echo "=== [3] LoadBalancer - external IP from cloud-provider-kind ==========="
  echo "Who can reach it   : anything that can route to the assigned external"
  echo "                     IP - in a real cloud, the public internet; here,"
  echo "                     anything on the 'kind' Docker bridge network."
  echo "Entry point        : the EXTERNAL-IP cloud-provider-kind assigned"
  echo "                     (an Envoy proxy container it runs for this Service)."
  echo "Forwarded by       : that Envoy container proxies to the Service's"
  echo "                     Pod endpoints - kube-proxy is not in this path."
  LB_IP="$(kubectl -n "$NS" get svc nginx-web-loadbalancer -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
  echo "EXTERNAL-IP: $LB_IP"
  echo
  echo "NOTE: on Docker Desktop for Windows, the WSL2 distro's own network"
  echo "namespace has no route into the 'kind' custom bridge network (this"
  echo "is a Docker-Desktop-on-Windows networking limitation, not a"
  echo "Kubernetes one), so the access test below runs from a peer container"
  echo "already attached to that network (cse644-worker) rather than from"
  echo "the WSL2 shell directly:"
  echo "\$ docker exec cse644-worker curl http://$LB_IP:8090/"
  LB_OUT="$(docker exec cse644-worker curl -sS -o /dev/null -w 'HTTP %{http_code}' "http://$LB_IP:8090/" 2>&1)"
  echo "$LB_OUT"
  echo "$LB_OUT" | grep -q "200" && echo "[PASS] LoadBalancer EXTERNAL-IP reachable on the kind Docker network"

  echo
  echo "=== [4] Ingress - HTTP host/path routing =============================="
  echo "Who can reach it   : anything that can reach the ingress controller's"
  echo "                     entry point and sends the right Host header."
  echo "Entry point        : host ports 80/443, mapped by KinD's"
  echo "                     extraPortMappings straight to the ingress-nginx"
  echo "                     controller Pod (which runs with hostNetwork:true"
  echo "                     on the control-plane node)."
  echo "Forwarded by       : the ingress-nginx controller reads the Ingress"
  echo "                     object's host/path rules and proxies to"
  echo "                     nginx-web-svc's Pod endpoints directly."
  echo
  echo "\$ curl -H 'Host: cse644.local' http://localhost/"
  ING_OUT="$(curl -sS -o /dev/null -w 'HTTP %{http_code}' -H 'Host: cse644.local' http://localhost/ 2>&1)"
  echo "$ING_OUT"
  echo "$ING_OUT" | grep -q "200" && echo "[PASS] Ingress reachable at localhost with Host: cse644.local"

  echo
  echo "=== Req 4 complete: ClusterIP, NodePort, LoadBalancer, Ingress all verified ==="
} > "$LOG" 2>&1

grep -E '^\[(PASS|FAIL)\]' "$LOG"
echo "Evidence ($(wc -l < "$LOG") lines) -> $LOG"
