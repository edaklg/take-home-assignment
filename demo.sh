#!/usr/bin/env bash
# End-to-end demo: start Minikube, install KEDA, deploy the chart, watch scaling.
set -euo pipefail

CHART_DIR="$(cd "$(dirname "$0")/charts/keda-demo" && pwd)"
RELEASE_NAME="keda-demo"
NAMESPACE="default"
KEDA_NAMESPACE="keda"

# ── colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[demo]${NC} $*"; }
warn()  { echo -e "${YELLOW}[demo]${NC} $*"; }

# ── 1. prereqs ───────────────────────────────────────────────────────────────
info "Checking prerequisites..."
for cmd in minikube helm kubectl; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' is not installed. See README.md for install instructions." >&2
    exit 1
  fi
done

# ── 2. Minikube ──────────────────────────────────────────────────────────────
if minikube status --profile minikube 2>/dev/null | grep -q "Running"; then
  info "Minikube already running."
else
  info "Starting Minikube..."
  minikube start --driver=docker --cpus=2 --memory=2048
fi

# ── 3. KEDA ──────────────────────────────────────────────────────────────────
info "Adding KEDA Helm repo..."
helm repo add kedacore https://kedacore.github.io/charts 2>/dev/null || true
helm repo update kedacore

if helm status keda -n "$KEDA_NAMESPACE" &>/dev/null; then
  info "KEDA already installed."
else
  info "Installing KEDA..."
  helm install keda kedacore/keda \
    --namespace "$KEDA_NAMESPACE" \
    --create-namespace \
    --wait \
    --timeout 120s
fi

info "Waiting for KEDA operator to be ready..."
kubectl wait deployment/keda-operator \
  -n "$KEDA_NAMESPACE" \
  --for=condition=Available \
  --timeout=120s

# ── 4. Chart ─────────────────────────────────────────────────────────────────
if helm status "$RELEASE_NAME" -n "$NAMESPACE" &>/dev/null; then
  info "Chart already installed; upgrading..."
  helm upgrade "$RELEASE_NAME" "$CHART_DIR" -n "$NAMESPACE"
else
  info "Installing keda-demo chart..."
  helm install "$RELEASE_NAME" "$CHART_DIR" -n "$NAMESPACE"
fi

# ── 5. Explain the schedule ──────────────────────────────────────────────────
cat <<'EOF'

  Cron schedule (UTC):
    Scale UP   → */2 * * * *   (minutes 0, 2, 4, …)  3 replicas
    Scale DOWN → 1/2 * * * *   (minutes 1, 3, 5, …)  0 replicas

  Watching for 6 minutes — you should see at least two full up/down cycles.
  Press Ctrl-C to stop early.

EOF

# ── 6. Watch ─────────────────────────────────────────────────────────────────
WATCH_SECONDS=360
INTERVAL=20
END_TIME=$(( $(date +%s) + WATCH_SECONDS ))

while [ "$(date +%s)" -lt "$END_TIME" ]; do
  echo "─────────────────────────────────── $(date -u '+%H:%M:%S UTC') ───"
  echo "Deployment:"
  kubectl get deployment "$RELEASE_NAME-keda-demo" \
    -n "$NAMESPACE" \
    -o wide \
    --no-headers 2>/dev/null \
    || kubectl get deployments -n "$NAMESPACE" --no-headers 2>/dev/null \
    || true
  echo ""
  echo "Pods:"
  kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE_NAME" \
    --no-headers 2>/dev/null || true
  echo ""
  echo "ScaledObject:"
  kubectl get scaledobject -n "$NAMESPACE" --no-headers 2>/dev/null || true
  echo ""
  sleep "$INTERVAL"
done

info "Demo complete. Run 'make clean' to tear everything down."
