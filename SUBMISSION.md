# CSE644 Cloud Computing — Kubernetes Assignment 02 · Submission

## Required submission items

| Item | Value |
|---|---|
| **Name** | Tray Branch |
| **Local Kubernetes environment used** | KinD (Kubernetes in Docker) v0.30.0, cluster `cse644` — 1 control-plane + 1 worker node, `kindest/node:v1.34.0` |
| **Local-image loading instructions** | Images are `docker build`-ed locally, then injected directly into the KinD nodes' containerd with `kind load docker-image ... --name cse644` (no registry involved). Every Deployment sets `imagePullPolicy: IfNotPresent`. Full detail in [`README.md`](README.md#local-image-loading) and [`scripts/01-build-and-load-images.sh`](scripts/01-build-and-load-images.sh). |
| **GitHub repository** | https://github.com/Auth3nticAI/cse644-k8s-assignment |
| **README architecture summary** | [`README.md`](README.md#architecture-summary) |

---

## Required evidence checklist

| # | Demonstration | Evidence |
|---|---|---|
| 1 | Functioning local Kubernetes cluster | [`00-cluster-verify.txt`](evidence/logs/00-cluster-verify.txt) |
| 2 | Public-image workload: create/run, inspect, logs, interactive exec | [`req01-public-image.txt`](evidence/logs/req01-public-image.txt) |
| 3 | Both app workloads operating (multi-instance web app, port-8888 app) | [`req02-app-deployment.txt`](evidence/logs/req02-app-deployment.txt) |
| 4 | Internal service discovery (labels/selectors → Endpoints, DNS resolution) | [`req02-app-deployment.txt`](evidence/logs/req02-app-deployment.txt) |
| 5 | HAProxy proxying to the web app via Service discovery | [`req03-haproxy-edge.txt`](evidence/logs/req03-haproxy-edge.txt) |
| 6 | ClusterIP, NodePort, LoadBalancer, and Ingress access | [`req04-service-exposure.txt`](evidence/logs/req04-service-exposure.txt) |
| 7 | Storage persistence after workload replacement | [`req05-persistent-storage.txt`](evidence/logs/req05-persistent-storage.txt) |
| 8 | Non-secret configuration (ConfigMap) changing app behavior | [`req06-config-secret-health.txt`](evidence/logs/req06-config-secret-health.txt) §A |
| 9 | Secret received without exposure | [`req06-config-secret-health.txt`](evidence/logs/req06-config-secret-health.txt) §B |
| 10 | Readiness/liveness health-check behavior | [`req06-config-secret-health.txt`](evidence/logs/req06-config-secret-health.txt) §C |
| 11 | Complete, reproducible repository | [`98-final-state-snapshot.txt`](evidence/logs/98-final-state-snapshot.txt) — whole platform at a glance |

Every `scripts/reqNN-*.sh` logs full detail to its matching `evidence/logs/reqNN-*.txt` and prints only
`[PASS]`/`[FAIL]` lines to the console; each is idempotent and safe to re-run.

---

## Requirement-to-artifact map

| Req | Artifact |
|---|---|
| Environment: install Docker + local K8s | KinD v0.30.0 on Docker Desktop 29.4.0 (WSL2 backend); [`kind/kind-config.yaml`](kind/kind-config.yaml) |
| 1 Kubernetes workload operations | [`k8s/01-public-image-pod.yaml`](k8s/01-public-image-pod.yaml) (busybox), [`scripts/req01-public-image.sh`](scripts/req01-public-image.sh) |
| 2 App deployment + internal discovery | [`k8s/02-nginx-deployment.yaml`](k8s/02-nginx-deployment.yaml), [`k8s/04-python-deployment.yaml`](k8s/04-python-deployment.yaml), + their Services |
| 3 HAProxy edge component | [`apps/haproxy/haproxy.cfg`](apps/haproxy/haproxy.cfg), [`k8s/06-haproxy-deployment.yaml`](k8s/06-haproxy-deployment.yaml) |
| 4 Service exposure comparison | [`k8s/03`](k8s/03-nginx-service-clusterip.yaml), [`08`](k8s/08-nginx-service-nodeport.yaml), [`09`](k8s/09-nginx-service-loadbalancer.yaml), [`10-nginx-ingress.yaml`](k8s/10-nginx-ingress.yaml) |
| 5 Persistent storage | [`k8s/11-python-pvc.yaml`](k8s/11-python-pvc.yaml) |
| 6 Configuration + health | [`k8s/12-python-configmap.yaml`](k8s/12-python-configmap.yaml), [`k8s/13-python-secret.yaml`](k8s/13-python-secret.yaml), probes in [`k8s/04-python-deployment.yaml`](k8s/04-python-deployment.yaml) |
| Source control + images | This repository; all image tags pinned to `:v1` (no `:latest`/floating tags) |
| Submit links | This file |

---

## Security statement

No password, kubeconfig, API key, private key, or environment file containing real secrets appears in this
repository or in any committed log.

The one committed `Secret` manifest ([`k8s/13-python-secret.yaml`](k8s/13-python-secret.yaml)) holds a
clearly-labeled **dummy** value (`dummy-api-key-DO-NOT-USE-93f7c2a1`) — safe to commit, per the assignment's
explicit "dummy or instructor-provided sensitive value" allowance. The application only ever reports whether
that value is *present* (`secret_loaded: true/false`); the evidence log
([`req06-config-secret-health.txt`](evidence/logs/req06-config-secret-health.txt) §B) explicitly checks the
HTTP response and `kubectl logs` output for the literal dummy value and confirms it appears in neither.

As required, the README states plainly that **Kubernetes Secrets are base64-encoded, not encrypted, in the API
server's underlying etcd store by default**, and identifies the two production mitigations: encryption at rest
(an `EncryptionConfiguration` on the API server) and least-privilege RBAC scoped to the specific
ServiceAccounts/users that need a given Secret. Full explanation in
[`README.md`](README.md#requirement-6-application-configuration-and-health).

[`scripts/secret-scan.sh`](scripts/secret-scan.sh) scans the whole tree for token-, key-, and password-shaped
strings (excluding the one intentional dummy value) and reported **CLEAN** before publishing.
