RELEASE      := keda-demo
CHART        := charts/keda-demo
NAMESPACE    := default
KEDA_NS      := keda

.PHONY: all cluster keda chart watch status clean

## all: full end-to-end demo (same as running ./demo.sh)
all: demo.sh
	@bash demo.sh

## cluster: start Minikube
cluster:
	minikube start --driver=docker --cpus=2 --memory=2048

## keda: install KEDA via Helm
keda:
	helm repo add kedacore https://kedacore.github.io/charts 2>/dev/null || true
	helm repo update kedacore
	helm upgrade --install keda kedacore/keda \
		--namespace $(KEDA_NS) \
		--create-namespace \
		--wait --timeout 120s

## chart: install (or upgrade) the keda-demo chart
chart:
	helm upgrade --install $(RELEASE) $(CHART) \
		--namespace $(NAMESPACE) \
		--wait --timeout 60s

## status: show current state of deployment, pods, and ScaledObject
status:
	@echo "=== Deployment ==="
	@kubectl get deployment -n $(NAMESPACE) -l "app.kubernetes.io/instance=$(RELEASE)" 2>/dev/null || true
	@echo ""
	@echo "=== Pods ==="
	@kubectl get pods -n $(NAMESPACE) -l "app.kubernetes.io/instance=$(RELEASE)" 2>/dev/null || true
	@echo ""
	@echo "=== ScaledObject ==="
	@kubectl get scaledobject -n $(NAMESPACE) 2>/dev/null || true

## watch: stream pod changes (Ctrl-C to stop)
watch:
	kubectl get pods -n $(NAMESPACE) -l "app.kubernetes.io/instance=$(RELEASE)" -w

## clean: remove the chart, KEDA, and stop Minikube
clean:
	-helm uninstall $(RELEASE) -n $(NAMESPACE) 2>/dev/null
	-helm uninstall keda -n $(KEDA_NS) 2>/dev/null
	-kubectl delete namespace $(KEDA_NS) 2>/dev/null
	minikube stop

## help: list available targets
help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
