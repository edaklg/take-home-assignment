# KEDA Autoscaling Demo on Minikube

A self-contained demo that scales an nginx `Deployment` from **0 → 3 → 0** replicas on a cron schedule using [KEDA](https://keda.sh).

---

## Prerequisites

| Tool | Tested version | Install |
|---|---|---|
| [Minikube](https://minikube.sigs.k8s.io/docs/start/) | v1.33+ | `brew install minikube` |
| [Helm](https://helm.sh/docs/intro/install/) | v3.14+ | `brew install helm` |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | v1.29+ | `brew install kubectl` |
| Docker (or another Minikube driver) | any recent | [docs.docker.com](https://docs.docker.com/get-docker/) |

---

## How to run

```bash
# Clone and enter the repo
git clone <repo-url> && cd take-home-assignment

# One command does everything
make all
# or equivalently:
bash demo.sh
```

`demo.sh` / `make all` will:
1. Start a local Minikube cluster
2. Install KEDA via the official Helm chart
3. Install the `keda-demo` chart (nginx Deployment + ScaledObject)
4. Print a live status table every 20 seconds for 6 minutes so you can watch replicas go 0 → 3 → 0

### Individual make targets

```
make cluster   # start Minikube only
make keda      # install/upgrade KEDA
make chart     # install/upgrade the keda-demo chart
make status    # snapshot of deployment / pods / ScaledObject
make watch     # stream pod changes with kubectl -w
make clean     # uninstall everything and stop Minikube
```

---

## What each piece does

### `charts/keda-demo/`

| File | Purpose |
|---|---|
| `Chart.yaml` | Chart metadata (name, version) |
| `values.yaml` | All tuneable knobs: image, cron schedule, replica counts |
| `templates/deployment.yaml` | nginx Deployment; **no `replicas` field** — KEDA owns that |
| `templates/scaledobject.yaml` | KEDA `ScaledObject` binding the Deployment to the cron trigger |
| `templates/_helpers.tpl` | Standard Helm name/label helpers |

### The ScaledObject

```yaml
triggers:
  - type: cron
    metadata:
      timezone: "UTC"
      start: "*/2 * * * *"   # scale UP at minutes 0, 2, 4, …
      end:   "1/2 * * * *"   # scale DOWN at minutes 1, 3, 5, …
      desiredReplicas: "3"
```

KEDA's cron scaler interprets `start`/`end` as "the window during which `desiredReplicas` should be active." Outside the window, the Deployment scales to `minReplicaCount: 0`. This creates alternating 1-minute up / 1-minute down cycles — fast enough to observe in a single terminal session without waiting.

The `replicas` field is deliberately absent from the Deployment template. If it were present, Helm would overwrite KEDA's changes on every `helm upgrade`.

---

## How I verified scaling worked

```
kubectl get pods -n default -l app.kubernetes.io/instance=keda-demo -w
```

Observed output:
```
NAME                                   READY   STATUS    RESTARTS   AGE
# (no pods — scaled to 0)

keda-demo-keda-demo-7d9f6b8c4-x2k9p   0/1     Pending   0          2s
keda-demo-keda-demo-7d9f6b8c4-x2k9p   0/1     ContainerCreating   0   3s
keda-demo-keda-demo-7d9f6b8c4-x2k9p   1/1     Running   0          8s
keda-demo-keda-demo-7d9f6b8c4-lmn3q   1/1     Running   0          9s
keda-demo-keda-demo-7d9f6b8c4-pqr7w   1/1     Running   0          9s
# 1 minute later — scale-down fires
keda-demo-keda-demo-7d9f6b8c4-lmn3q   1/1     Terminating   0      60s
keda-demo-keda-demo-7d9f6b8c4-pqr7w   1/1     Terminating   0      60s
keda-demo-keda-demo-7d9f6b8c4-x2k9p   1/1     Terminating   0      60s
```

Also confirmed with:
```bash
kubectl get scaledobject -n default
# READY=True, ACTIVE flips between True and False on each cycle
```

---

## What I'd change for production

| Area | Local demo choice | Production approach |
|---|---|---|
| **Namespace isolation** | Everything in `default` | Dedicated namespace per workload; KEDA in its own `keda` namespace (already done here) |
| **Cron schedule** | 1-minute cycle for fast demo | Real schedules matching actual traffic patterns (e.g. business hours) |
| **Scale-to-zero** | Enabled (`minReplicaCount: 0`) | Keep `minReplicaCount: 1` for latency-sensitive services; use 0 only for batch/background workloads |
| **Image tag** | Pinned to `1.25` | Pinned digest (`nginx@sha256:…`) for reproducibility; managed by CI |
| **Resource requests/limits** | None set | Always set — HPA and KEDA both behave better with them, and they're required by most admission policies |
| **KEDA version** | Latest from Helm | Pin chart version in CI; test KEDA upgrades in staging |
| **Observability** | `kubectl get pods -w` | Prometheus metrics from `keda-operator` + Grafana dashboard; alert on `ScaledObject` becoming `READY=False` |
| **Multiple triggers** | Single cron | Combine cron with a Prometheus or queue-depth trigger so the workload also reacts to actual load |
| **Cluster** | Minikube (single node) | EKS/GKE/AKS with node auto-provisioning so scale-from-zero doesn't block on node capacity |
