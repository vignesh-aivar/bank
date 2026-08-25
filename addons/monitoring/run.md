# Monitoring Stack Installation

All images are pulled from `public.ecr.aws/u7h9i3k7/monitoring/*`.

All components run on the **monitoring nodepool** (`NodeGroupType: monitoring`) with taint toleration (`workload=monitoring:NoSchedule`), except:
- **OTel Collector** — DaemonSet that runs on ALL nodes (tolerates all taints)
- **Node Exporter** — DaemonSet that runs on ALL nodes (tolerates all taints)

## Prerequisites

```bash
kubectl create namespace monitoring
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
```

## 1. Kube Prometheus Stack

Installs Prometheus, Alertmanager, Grafana, Node Exporter, Kube State Metrics, and Prometheus Operator.

```bash
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f kube-prometheus-stack-values.yaml \
  --wait
```

## 2. Loki

Log aggregation (SingleBinary mode, filesystem storage, 7d retention).

```bash
helm upgrade --install loki grafana/loki \
  --namespace monitoring \
  -f loki-values.yaml \
  --wait
```

## 3. Tempo

Distributed tracing (S3 backend, 30d retention).

```bash
helm upgrade --install tempo grafana/tempo-distributed \
  --namespace monitoring \
  -f tempo-values.yaml \
  --wait
```

## 4. OpenTelemetry Collector

DaemonSet that collects logs from all pods and receives OTLP traces from applications.

```bash
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  --namespace monitoring \
  -f otel-collector-values.yaml \
  --wait
```

## 5. Prometheus Adapter

Custom metrics API for HPA scaling (exposes `livekit_egress_requests`).

```bash
helm upgrade --install prometheus-adapter prometheus-community/prometheus-adapter \
  --namespace monitoring \
  -f prometheus-adapter-values.yaml \
  --wait
```

## Images Used

| Component | Image |
|-----------|-------|
| Prometheus Operator | `public.ecr.aws/u7h9i3k7/monitoring/prometheus-operator` |
| Prometheus Config Reloader | `public.ecr.aws/u7h9i3k7/monitoring/prometheus-config-reloader` |
| Prometheus | `public.ecr.aws/u7h9i3k7/monitoring/prometheus` |
| Alertmanager | `public.ecr.aws/u7h9i3k7/monitoring/alertmanager` |
| Grafana | `public.ecr.aws/u7h9i3k7/monitoring/grafana` |
| Grafana Init (busybox) | `public.ecr.aws/u7h9i3k7/monitoring/busybox` |
| Grafana Sidecar | `public.ecr.aws/u7h9i3k7/monitoring/k8s-sidecar` |
| Node Exporter | `public.ecr.aws/u7h9i3k7/monitoring/node-exporter` |
| Kube State Metrics | `public.ecr.aws/u7h9i3k7/monitoring/kube-state-metrics` |
| Loki | `public.ecr.aws/u7h9i3k7/monitoring/loki` |
| Loki Gateway (nginx) | `public.ecr.aws/u7h9i3k7/monitoring/nginx-unprivileged` |
| Loki Sidecar | `public.ecr.aws/u7h9i3k7/monitoring/k8s-sidecar` |
| Tempo | `public.ecr.aws/u7h9i3k7/monitoring/tempo` |
| OTel Collector | `public.ecr.aws/u7h9i3k7/monitoring/otel-collector-contrib` |
| Prometheus Adapter | `public.ecr.aws/u7h9i3k7/monitoring/prometheus-adapter` |

## Verification

```bash
# Check all pods are running
kubectl get pods -n monitoring

# Verify images are from public ECR
kubectl get pods -n monitoring -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{"\n"}{end}{end}'

# Check node placement (monitoring nodepool)
kubectl get pods -n monitoring -o wide

# Verify DaemonSets run on all nodes
kubectl get daemonset -n monitoring

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-prometheus 9090:9090
# Visit http://localhost:9090/targets

# Check Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Visit http://localhost:3000 (admin/changeme)

# Check Loki is receiving logs
kubectl port-forward -n monitoring svc/loki-gateway 3100:80
curl -s http://localhost:3100/loki/api/v1/labels | jq .

# Check custom metrics API (prometheus-adapter)
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq .
```
