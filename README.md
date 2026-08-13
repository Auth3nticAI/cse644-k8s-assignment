# CSE644 Assignment 02 - Local Kubernetes Application Platform

**Student:** Tray Branch
**Local Kubernetes environment:** [KinD](https://kind.sigs.k8s.io/) (Kubernetes in Docker), v0.30.0, cluster name `cse644`
**Kubernetes node image:** `kindest/node:v1.34.0`
**Repository:** https://github.com/Auth3nticAI/cse644-k8s-assignment

## Why KinD

The assignment allows Minikube, KinD, or Docker Desktop Kubernetes. KinD was chosen because it runs the whole
cluster as plain Docker containers (no extra hypervisor/VM), it's fully scriptable from a clean `kind create
cluster --config ...` (nothing to click through in a GUI), and a 2-node config (control-plane + worker) gives a
more realistic "multiple instances land on different nodes" story than a single-node cluster.

## Architecture summary

```
                                 host (Windows / WSL2)
                                          |
        +---------------------+----------+----------------------+
        |                     |                                 |
   localhost:30080      localhost:80/443             172.22.0.x:8090
   (NodePort)           (Ingress, Host: cse644.local)  (LoadBalancer EXTERNAL-IP,
        |                     |                          via cloud-provider-kind)
        v                     v                                 |
  +-----------+      +------------------+                       |
  | kube-proxy|      | ingress-nginx    |                       |
  | (every    |      | controller       |                       |
  |  node)    |      | (hostNetwork)    |                       |
  +-----+-----+      +--------+---------+                       |
        |                     |                                 |
        +----------+----------+---------------------------------+
                   v
          nginx-web-svc (ClusterIP)  <---- also reached by:
                   |                        - HAProxy edge (Deployment, its own
                   v                          Pod) via this same Service DNS name
        +---------------------+               - public-image-demo Pod (busybox)
        | nginx-web Deployment |               for internal-discovery tests
        | 3 replicas            |
        +---------------------+

        python-web-svc (ClusterIP) --> python-web Deployment (1 replica)
                                          |  envFrom: python-web-config (ConfigMap)
                                          |           python-web-secret (Secret)
                                          |  volumeMount: /data <- python-web-data (PVC)
                                          |  livenessProbe: /healthz
                                          |  readinessProbe: /readyz
```

Namespace: everything application-related lives in `cse644`. The ingress-nginx controller lives in its own
`ingress-nginx` namespace (its own upstream manifest).

## Repository layout

```
apps/nginx-web/    Dockerfile + custom nginx page/config (the "customized web application")
apps/python-web/   Dockerfile + Flask app on :8888 (ConfigMap/Secret/PVC/health aware)
apps/haproxy/      Dockerfile + haproxy.cfg (edge component, Req 3)
kind/              KinD cluster config (node layout, port mappings)
k8s/               All Kubernetes manifests, applied in numeric order
k8s/vendor/        Vendored, version-pinned third-party manifest (ingress-nginx)
scripts/           Setup scripts (00-03, 99) and one evidence script per requirement (req01-req06)
evidence/logs/     Captured command output from each scripts/reqNN-*.sh run
```

## Prerequisites

- Docker Desktop (WSL2 backend), running
- WSL2 Ubuntu with: `docker`, `kubectl` (v1.34+), `git`
- `kind` and `cloud-provider-kind` - installed by the setup scripts below into `~/.local/bin` (no sudo/root needed)

## Local image loading

No image registry is used. Images are built locally with `docker build` and injected directly into the KinD
node containers' containerd image store with:

```bash
kind load docker-image auth3nticai/cse644-k8s-nginx:v1 auth3nticai/cse644-k8s-python:v1 auth3nticai/cse644-k8s-haproxy:v1 --name cse644
```

Every Deployment sets `imagePullPolicy: IfNotPresent` so the kubelet uses the loaded image instead of trying
to pull from a registry. All three images use a fixed `:v1` tag (never `:latest` or unversioned) per the
assignment's no-floating-tags rule.

## Deployment instructions

```bash
bash scripts/00-bootstrap-cluster.sh        # kind create cluster + ingress-nginx controller
bash scripts/01-build-and-load-images.sh    # docker build x3 + kind load docker-image
bash scripts/02-run-cloud-provider-kind.sh  # installs + starts the LoadBalancer provider (background)
bash scripts/03-apply-all-manifests.sh      # kubectl apply -f k8s/*.yaml in order, waits for rollout
```

## Validation steps (evidence)

Each requirement has its own idempotent, re-runnable script. Every script logs full detail to
`evidence/logs/reqNN-*.txt` and prints only `[PASS]`/`[FAIL]` lines to the console.

| Script | Requirement |
|---|---|
| `scripts/req01-public-image.sh` | Kubernetes Workload Operations (public busybox image: create, inspect, logs, exec) |
| `scripts/req02-app-deployment.sh` | App deployment + internal service discovery |
| `scripts/req03-haproxy-edge.sh` | HAProxy edge component via Service discovery |
| `scripts/req04-service-exposure.sh` | ClusterIP / NodePort / LoadBalancer / Ingress |
| `scripts/req05-persistent-storage.sh` | Persistent storage (write, replace Pod, verify) |
| `scripts/req06-config-secret-health.sh` | ConfigMap, Secret, readiness/liveness |

## Requirement 1: public-image workload operations

`k8s/01-public-image-pod.yaml` runs a `busybox:1.36.1` Pod (a public image, not one we built) that loops
printing timestamped lines. `scripts/req01-public-image.sh` demonstrates, in order: `kubectl apply` (create/run),
`kubectl get -o wide` + `kubectl describe` (inspect), `kubectl logs` (output), and `kubectl exec` running a
shell session inside the container (writes a file, then a second `exec` reads it back to prove state persisted
in that same running container).

## Requirement 2: application deployment and internal discovery

- `nginx-web` Deployment: 3 replicas, Service `nginx-web-svc` (ClusterIP), labels `app=nginx-web`.
- `python-web` Deployment: 1 replica (see Requirement 5 for why), Service `python-web-svc` (ClusterIP) on
  `:8888`, labels `app=python-web`.
- The Service `spec.selector` on each is checked against the Deployment's Pod-template labels, and against
  `kubectl get endpoints`, to prove the selector is actually matching live Pod IPs, not just superficially
  "configured."
- Internal discovery is demonstrated from the Requirement-1 busybox Pod: `nslookup nginx-web-svc.cse644.svc.cluster.local`
  resolves, and repeated requests return different `X-CSE644-Served-By` (Pod hostname) values, proving the
  Service is genuinely load-balancing across multiple running Pod instances rather than hitting a single one.

## Requirement 3: HAProxy edge component

`apps/haproxy/haproxy.cfg`'s backend has exactly **one** `server` line, and it points at
`nginx-web-svc.cse644.svc.cluster.local:80` - the Service's DNS name - never a Pod IP or Pod name. Kubernetes'
own kube-proxy already load-balances across whichever nginx-web Pods are Ready behind that Service; HAProxy
does not maintain its own list of backend Pod addresses, so Pods can be added, removed, or rescheduled without
ever touching this config. `scripts/req03-haproxy-edge.sh` sends four requests through HAProxy's own Service
(`haproxy-edge-svc`) and shows the `X-CSE644-Proxy: haproxy` header (proves the hop went through HAProxy) plus
a changing `X-CSE644-Served-By` header (proves HAProxy's single Service-DNS backend is still reaching multiple
distinct nginx-web Pods).

## Requirement 4: Service exposure comparison

All four mechanisms front the same `nginx-web` Deployment (`k8s/02-nginx-deployment.yaml`), so the only
variable being compared is the exposure mechanism itself.

| Mechanism | Manifest | Who can reach it | Where the request enters | What forwards it to the workload |
|---|---|---|---|---|
| **ClusterIP** | `k8s/03-nginx-service-clusterip.yaml` | Only clients inside the cluster's Pod network, or an operator tunneling in | The Service's ClusterIP (a virtual IP, cluster-internal only) | **kube-proxy** (iptables/nftables rules on every node) rewrites ClusterIP:port to a live Pod IP:port |
| **NodePort** | `k8s/08-nginx-service-nodeport.yaml` | Anything that can reach any cluster node's IP - e.g. other hosts on the node's LAN, not just cluster-internal | Port `30080`, opened on **every** node | **kube-proxy** on whichever node received the connection, forwarding to a live Pod endpoint (possibly on a different node) |
| **LoadBalancer** | `k8s/09-nginx-service-loadbalancer.yaml` | Anything that can route to the assigned external IP - the public internet in a real cloud; here, anything on the `kind` Docker bridge network | The `EXTERNAL-IP` that `cloud-provider-kind` assigns (a small Envoy proxy container it runs per Service) | That **Envoy proxy container** - kube-proxy is not in this path at all |
| **Ingress** | `k8s/10-nginx-ingress.yaml` | Anything that can reach the ingress controller's entry point and sends the matching `Host` header | Host ports `80`/`443`, mapped by KinD straight through to the ingress-nginx controller Pod (`hostNetwork: true`) | The **ingress-nginx controller**, which reads the `Ingress` object's host/path rules and proxies HTTP directly to Pod endpoints |

Local access proof for each (see `evidence/logs/req04-service-exposure.txt` for full output):
- ClusterIP: `kubectl -n cse644 port-forward svc/nginx-web-svc 18080:80`, then `curl localhost:18080` -> `200`
- NodePort: `curl localhost:30080` -> `200` (KinD's `extraPortMappings` maps host `30080` to the control-plane node)
- LoadBalancer: `curl <EXTERNAL-IP>:8090` -> `200`
- Ingress: `curl -H "Host: cse644.local" localhost` -> `200`

### Two setup notes worth knowing about

**LoadBalancer needs a helper.** KinD has no cloud provider, so a `type: LoadBalancer` Service normally sits at
`<pending>` forever. [`cloud-provider-kind`](https://github.com/kubernetes-sigs/cloud-provider-kind) is the
standard local stand-in - it watches for LoadBalancer Services and runs a small Envoy proxy container on the
`kind` Docker network that gets a real IP. Two things had to be worked around to get it working here:
1. The vendored ingress-nginx manifest's own Service defaults to `type: LoadBalancer` too, which made
   `cloud-provider-kind` fight with KinD's own `extraPortMappings` over host port 80/443. It's patched to
   `type: ClusterIP` in `k8s/vendor/...yaml` (that controller Pod already uses `hostNetwork: true`, so it
   doesn't need a LoadBalancer of its own).
2. Host port `8080` (a natural default) turned out to already be in use by an unrelated container on this
   machine, so the `nginx-web-loadbalancer` Service uses `8090` instead - a reminder to always check
   `docker ps` for port collisions before picking one.

**On Docker Desktop for Windows, WSL2 can't directly route to the `kind` Docker network.** The `EXTERNAL-IP`
`cloud-provider-kind` assigns (e.g. `172.22.0.4`) lives on the custom `kind` bridge network; unlike Docker's
default bridge, Docker Desktop's WSL2 integration does not add a route to it from inside a WSL distro. This is
a Windows/Docker-Desktop networking limitation, not a Kubernetes one. The access test therefore runs `curl`
from a peer container already on that network (`docker exec cse644-worker curl ...`) - a "local access method
appropriate to your selected Kubernetes environment," as the assignment allows.

## Requirement 5: persistent storage

`k8s/11-python-pvc.yaml` requests a 100Mi `PersistentVolumeClaim` (`python-web-data`) against KinD's default
`standard` StorageClass (`rancher.io/local-path`), which dynamically provisions a `hostPath` directory on
whichever node the claim binds to. It's mounted at `/data` in the `python-web` container
(`k8s/04-python-deployment.yaml`), where `app.py`'s `/api/notes` endpoint appends to `/data/notes.log`.

Because that volume is `ReadWriteOnce` and node-local, `python-web` runs as **1 replica**, not 3 - a second
replica could only ever be scheduled on the same node as the first, and this requirement is specifically about
one workload being *replaced*, not multiple replicas concurrently sharing one local volume.

`scripts/req05-persistent-storage.sh`:
1. Writes a uniquely-timestamped note through the running Pod (`POST /api/notes`).
2. Deletes that Pod outright (`kubectl delete pod`) - the Deployment replaces it with a **new** Pod (different
   name, confirmed in the evidence).
3. Reads `/data/notes.log` from the **new** Pod and confirms the note written by the old Pod is still there.

The container's own writable layer would have been wiped along with the old Pod; the PVC is what survived.

## Requirement 6: application configuration and health

**ConfigMap** (`k8s/12-python-configmap.yaml`, keys `APP_GREETING` / `APP_ENVIRONMENT`) is injected as env vars
via `envFrom.configMapRef`. `scripts/req06-config-secret-health.sh` captures the live greeting *before* editing
the ConfigMap, then re-applies the (updated) manifest and does a `kubectl rollout restart` (env vars are only
read at container start, so a restart is required for the new value to take effect), then shows the *after*
response - same app, same image, different visible text, no rebuild.

**Secret** (`k8s/13-python-secret.yaml`, `type: Opaque`, key `APP_SECRET_VALUE`) holds a clearly-labeled
**dummy** value (`dummy-api-key-DO-NOT-USE-93f7c2a1`) - safe to commit, not a real credential. It's injected
the same way as the ConfigMap (`envFrom.secretRef`). `app.py` only ever reports `secret_loaded: true/false` -
the raw value is never logged, never rendered on the page, and never returned by any endpoint. The evidence
script explicitly greps the HTTP response and the container's own `kubectl logs` output for the literal dummy
value and confirms it never appears in either.

> **Kubernetes Secrets are not encrypted by default.** By default the API server stores Secret data in etcd
> **base64-encoded, not encrypted** - base64 is an encoding, not a cipher, and anyone with etcd access (or a
> backup of it) can trivially decode it. In a production cluster this needs: **encryption at rest** (an
> `EncryptionConfiguration` with a KMS or `aescbc` provider on the API server, so etcd itself only ever holds
> ciphertext) and **least-privilege RBAC** (Roles/RoleBindings scoped so only the specific ServiceAccounts and
> humans that truly need a given Secret can `get`/`list` it - `get secrets` cluster-wide is a common
> over-grant to avoid).

**Readiness vs. liveness**, both on `python-web`:
- **Liveness (`/healthz`)** answers "is the process itself still able to respond at all?" It has no external
  dependency on purpose - a slow disk or a temporarily-missing Secret must never cause Kubernetes to conclude
  the *process* is broken and restart-loop it.
- **Readiness (`/readyz`)** answers "are this Pod's actual dependencies in place?" - it checks that `/data` is
  writable (the PVC is mounted), that `APP_GREETING` is non-empty (the ConfigMap is present and populated),
  and that the Secret loaded. If any check fails it returns `503`, which pulls the Pod out of
  `python-web-svc`'s Endpoints (no traffic sent to it) **without** killing or restarting it.

The evidence script proves this distinction is real, not just documented: it blanks `APP_GREETING` in the live
ConfigMap and restarts the Deployment. The new Pod comes up `Running` but `0/1 Ready` (`/readyz` correctly
returns `503` with `"greeting_configured": false` in the body), stays at **0 restarts** the entire time (proving
liveness never fired), and disappears from `python-web-svc`'s Endpoints while the Deployment safely keeps the
previous good Pod serving traffic. Restoring the ConfigMap and restarting again brings the new Pod to `1/1
Ready`, rejoining the Service.

## Cleanup

```bash
bash scripts/99-cleanup.sh
```

Stops `cloud-provider-kind`, deletes the `cse644` KinD cluster (which takes every Deployment/Service/PVC/etc.
with it), and removes the three locally built images.

## Security notes

- No real credentials, tokens, kubeconfig files, or private keys are committed anywhere in this repository.
- The one committed Secret manifest (`k8s/13-python-secret.yaml`) holds a clearly-labeled dummy value only,
  per the assignment's explicit "dummy or instructor-provided sensitive value" allowance.
- `.gitignore` does **not** use a blanket `*secret*` pattern (unlike a stricter template) specifically because
  that would have hidden the Secret manifest this assignment requires tracking; `.gitattributes` normalizes
  line endings so `haproxy.cfg` and the shell scripts never break with a `^M`/`bad interpreter` error when run
  inside a Linux container.
