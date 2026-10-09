# .NET OpenTelemetry demo on AKS with Prometheus and Grafana

Deploys the Pluralsight "Observability with OpenTelemetry and Grafana" demo (Catalog.API, Basket.API, ServiceWorker, RabbitMQ) to Azure AKS and shows **Kubernetes cluster metrics in Grafana** (kube-prometheus-stack) plus the application's OpenTelemetry metrics.

```
Basket.API ─┐                              ┌─> Prometheus ─> Grafana
Catalog.API ┼─ OTLP :4317 ─> OTel Collector ─ :8889 (ServiceMonitor)
Worker ─────┘        (traces/logs -> debug exporter)

kubelet/cAdvisor, node-exporter, kube-state-metrics ──> Prometheus ──> built-in K8s dashboards
```

Images (single Docker Hub repo, one tag per service):
`alboner/plurasight-project:catalog-api`, `:basket-api`, `:service-worker`

## Layout

| Path | Content |
|---|---|
| `src/` | .NET 7 solution + one Dockerfile per service |
| `k8s/` | Namespaces, RabbitMQ, OTel Collector, apps, ServiceMonitor, traffic generator |
| `monitoring/` | `kps-values.yaml` (kube-prometheus-stack for AKS), `kps-values-small.yaml` (single-node overrides), app dashboard JSON |
| `scripts/` | `sandbox.env`, `preflight.sh`, `create-aks.sh`, `build-push.sh`, `deploy.sh` |
| `infra/local-compose/` | Original docker-compose stack (local only, not used on AKS) |

Changes made to the original code so it runs in Kubernetes: RabbitMQ host/credentials (`RabbitMQ:Host|Username|Password`) and Catalog URL (`Catalog:BaseUrl`) are now configuration values instead of hardcoded `localhost`. Defaults still work locally.

## 0. Prerequisites

Docker, Git, Azure CLI, kubectl (installed). Helm is needed:

```bash
winget install Helm.Helm        # then reopen the terminal
```

## 1. Push the code to GitHub

```bash
cd plurasight-project
git init -b main
git add .
git commit -m "Deploy .NET OTel demo to AKS with Prometheus and Grafana"
git remote add origin https://github.com/alhassandiallo/Plurasight-project.git
git push -u origin main
```

## 2. Build and push the Docker images

```bash
docker login -u alboner                 # use a Docker Hub access token as the password
./scripts/build-push.sh --push
```

Images are built for `linux/amd64` (AKS nodes). Without `--push` they are only built locally.

## 3. Provision AKS in the Pluralsight sandbox

Sandbox values are in `scripts/sandbox.env` (subscription `P8-Real Hands-On Labs`, `9734ed68-621d-47ed-babd-269110dbacb1`, resource group matching `7e8f4c7b`). The leading `## ` shown on the Pluralsight page is most likely a display artifact; the scripts look the group up by name and then by the `7e8f4c7b` fragment. If neither matches, `preflight.sh` prints `az group list` and you fix `RG_NAME` in `scripts/sandbox.env`.

```bash
az login                                # sandbox credentials from the Pluralsight page
./scripts/preflight.sh                  # read-only: finds RG, region, quota, allowed VM sizes, policies
./scripts/create-aks.sh                 # creates the cluster, trying each allowed VM size in turn
```

`preflight.sh` writes `scripts/.sandbox.resolved.env` (git-ignored). `create-aks.sh` reads it, skips creation if the cluster already exists, then runs `az aks get-credentials` and `kubectl get nodes`.

Target is 2 nodes of 2 vCPU / 4+ GiB. If the quota only allows one node, `NODE_COUNT=1` is set and `deploy.sh` automatically adds `monitoring/kps-values-small.yaml` (lighter limits). To force a specific size: `NODE_SIZES_OVERRIDE="Standard_D2s_v3" ./scripts/create-aks.sh`.

If the sandbox blocks AKS creation outright (policy denies `Microsoft.ContainerService` or the `MC_` node resource group), the error is printed by `create-aks.sh` and a personal Azure subscription is needed.

## 4. Deploy monitoring and the app

```bash
./scripts/deploy.sh
```

This installs `kube-prometheus-stack` (release `kps`, namespace `monitoring`), creates the collector ConfigMap, applies the app manifests, the ServiceMonitor and the custom dashboard.

## 5. Open Grafana

```bash
kubectl port-forward -n monitoring svc/kps-grafana 3000:80
```

Open http://localhost:3000, login `admin` / `admin-change-me`. Set your own password at deploy time with `GRAFANA_PASSWORD='...' ./scripts/deploy.sh`.

Dashboards > Browse:

- **Kubernetes / Compute Resources / Cluster** (and Namespace, Node, Pod): CPU, memory per namespace and pod. Select namespace `demo`.
- **Node Exporter / Nodes**: node CPU, memory, disk, network.
- **Kubernetes / Kubelet**, **Kubernetes / Networking / Cluster**.
- **.NET OTel Demo - Services**: request rate, p95 latency, GC heap, thread pool per service.

The `traffic-generator` deployment calls the APIs every 2 seconds so the charts have data. Allow 2-3 minutes after deploy.

## 6. Verify Prometheus

```bash
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090
```

http://localhost:9090/targets: `serviceMonitor/monitoring/otel-collector` and the kubelet, node-exporter and kube-state-metrics targets should be UP. Query examples:

```promql
sum by (namespace) (rate(container_cpu_usage_seconds_total{container!=""}[5m]))
sum by (service_name) (rate(http_server_duration_milliseconds_count[1m]))
```

## Troubleshooting

| Symptom | Check |
|---|---|
| Pods `ImagePullBackOff` | Images pushed? `kubectl describe pod -n demo <pod>`; Docker Hub repo must be public |
| Pods `Pending` | `kubectl describe pod`; not enough CPU/memory on the nodes, add nodes or a larger size |
| basket-api 500 on checkout | `kubectl logs -n demo deploy/basket-api`; RabbitMQ not ready or wrong credentials |
| Collector target missing in Prometheus | ServiceMonitor must have label `release: kps`; Helm release name must be `kps` |
| Grafana `Service kps-grafana` not found | `kubectl get svc -n monitoring` for the actual name |
| Empty .NET dashboard | Wait 2-3 min; run `kubectl logs -n demo deploy/otel-collector` |
| `create-aks.sh` fails for every size | Read the printed error: `RequestDisallowedByPolicy` (region/SKU/tag policy), `QuotaExceeded`, or provider not registered. Try `NODE_SIZES_OVERRIDE` or another size from `preflight.sh` |
| `deploy.sh`: wrong kubectl context | `az aks get-credentials -g <rg> -n aks-otel-demo --overwrite-existing` |
| `helm: command not found` | `winget install Helm.Helm`, reopen the terminal |

## Cleanup (cost / sandbox limits)

Sandboxes are time-limited and deleted automatically, so run the whole sequence in one session. To clean up early:

```bash
source scripts/.sandbox.resolved.env
az aks delete -g "$RG" -n aks-otel-demo --yes --no-wait
```

## Notes

- .NET 7 is end-of-life; it is kept to match the original course code. Upgrading means changing the TargetFramework and Dockerfile base tags.
- Traces and logs reach the collector but are only sent to the `debug` exporter. Add Tempo/Loki exporters in `k8s/otel-collector-config.yaml` to store them.
- Prometheus uses ephemeral storage with 6h retention (sandbox only; use a PVC in real clusters).
