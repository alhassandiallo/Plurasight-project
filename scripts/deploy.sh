#!/usr/bin/env bash
# Deploy monitoring stack + demo app to the AKS cluster created by create-aks.sh.
# Usage: ./scripts/deploy.sh            (optional: GRAFANA_PASSWORD=... to override the default)
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/sandbox.env
[[ -f scripts/.sandbox.resolved.env ]] && source scripts/.sandbox.resolved.env

command -v helm >/dev/null || { echo "helm not found. Install: winget install Helm.Helm (then reopen the terminal)" >&2; exit 1; }
ctx=$(kubectl config current-context 2>/dev/null || true)
[[ "$ctx" == *"$CLUSTER"* ]] || { echo "kubectl context is '$ctx', expected the '$CLUSTER' cluster. Run: az aks get-credentials -g <rg> -n $CLUSTER" >&2; exit 1; }
echo "kubectl context: $ctx"

VALUES=(--values monitoring/kps-values.yaml)
[[ "${NODE_COUNT:-2}" == "1" ]] && VALUES+=(--values monitoring/kps-values-small.yaml)
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin-change-me}"

echo "==> Namespaces"
kubectl apply -f k8s/00-namespaces.yaml

echo "==> kube-prometheus-stack (release name must be 'kps')"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update >/dev/null
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  "${VALUES[@]}" \
  --set grafana.adminPassword="$GRAFANA_PASSWORD" \
  --wait --timeout 10m

echo "==> OpenTelemetry Collector config"
kubectl create configmap otel-collector-config -n demo \
  --from-file=config.yaml=k8s/otel-collector-config.yaml \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Demo application"
kubectl apply -f k8s/10-rabbitmq.yaml
kubectl apply -f k8s/20-otel-collector.yaml
kubectl apply -f k8s/30-catalog-api.yaml
kubectl apply -f k8s/40-basket-api.yaml
kubectl apply -f k8s/50-service-worker.yaml
kubectl apply -f k8s/70-traffic-generator.yaml

echo "==> ServiceMonitor + custom Grafana dashboard"
kubectl apply -f k8s/60-servicemonitor.yaml
kubectl create configmap dotnet-otel-dashboard -n monitoring \
  --from-file=dotnet-otel-dashboard.json=monitoring/dotnet-otel-dashboard.json \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap dotnet-otel-dashboard -n monitoring grafana_dashboard=1 --overwrite

echo "==> Waiting for app pods"
kubectl rollout status deployment -n demo --timeout=300s \
  rabbitmq otel-collector catalog-api basket-api service-worker

echo
kubectl get pods -A -o wide | grep -E "^(demo|monitoring)"
echo
echo "Done. Open Grafana with:"
echo "  kubectl port-forward -n monitoring svc/kps-grafana 3000:80"
echo "  http://localhost:3000   (admin / $GRAFANA_PASSWORD)"
