# Monitoring Stack — Architecture & Components Explained

## Why it's called LGTM

**L**oki + **G**rafana + **T**empo + **M**imir (or Prometheus)

Each letter handles one observability signal:
- **L**oki → Logs
- **G**rafana → Visualization (dashboards, alerting UI)
- **T**empo → Traces
- **M**imir/Prometheus → Metrics

We use Prometheus instead of Mimir (same PromQL, single-instance vs distributed), so it's technically LGTP but the industry calls it LGTM.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        DATA SOURCES                              │
├─────────────────────────────────────────────────────────────────┤
│ kubelet/cAdvisor  kube-apiserver  Node Exporter  kube-state     │
│ App /metrics      LiveKit :6789   CoreDNS        Pod logs       │
│ App OTLP traces                                                 │
└────────┬──────────────┬───────────────┬──────────────┬──────────┘
         │ Metrics      │ Metrics       │ Logs         │ Traces
         ▼              ▼               ▼              ▼
   ┌───────────┐  ┌──────────┐  ┌────────────┐  ┌──────────┐
   │Prometheus │  │Prometheus│  │OTel        │  │OTel      │
   │(scrapes)  │  │(scrapes) │  │Collector   │  │Collector │
   └─────┬─────┘  └────┬─────┘  │(filelog)   │  │(OTLP rx) │
         │              │        └─────┬──────┘  └─────┬────┘
         │              │              │               │
         ▼              ▼              ▼               ▼
   ┌─────────────────────┐      ┌──────────┐    ┌──────────┐
   │     Prometheus      │      │   Loki   │    │  Tempo   │
   │     (TSDB)          │      │ (chunks) │    │  (S3)    │
   └──────────┬──────────┘      └────┬─────┘    └────┬─────┘
              │                      │               │
              └──────────┬───────────┴───────────────┘
                         │
                         ▼
                   ┌──────────┐
                   │ Grafana  │ ← Single pane of glass
                   └──────────┘
```

---

## Components by Category

---

### 1. PROMETHEUS (Metrics)

**What it does:** Scrapes metrics from targets at regular intervals, stores time-series data, provides PromQL query language.

#### Containers

| Container | Image | Tag | Role |
|-----------|-------|-----|------|
| Main | `prometheus` | `v3.3.1` | TSDB + scraping + PromQL engine |
| Sidecar | `prometheus-config-reloader` | `v0.82.0` | Watches for config/rule changes, triggers hot reload |

#### Deployment Details

| Property | Value |
|----------|-------|
| Deployed as | StatefulSet (1 replica) |
| PVC | 20Gi gp3 (TSDB storage) |
| Retention | 7 days / 18GB |
| Endpoint | `prometheus-prometheus.monitoring.svc.cluster.local:9090` |

#### What Prometheus Scrapes (data sources)

| Source | What it provides | Port/Path | Discovery |
|--------|-----------------|-----------|-----------|
| kubelet (cAdvisor) | Container CPU, memory, network, disk IO | `:10250/metrics/cadvisor` | Auto (kubelet ServiceMonitor) |
| kube-apiserver | API request latency, rate, errors | `:6443/metrics` | Auto (ServiceMonitor) |
| kube-proxy | Network rules sync latency | `:10249/metrics` | Auto (ServiceMonitor) |
| CoreDNS | DNS query rate, latency, cache hits | `:9153/metrics` | Auto (ServiceMonitor) |
| Node Exporter | Host CPU, disk, memory, network | `:9100/metrics` | ServiceMonitor |
| kube-state-metrics | Deployment replicas, pod status, HPA state | `:8080/metrics` | ServiceMonitor |
| Convogent backend | App `/metrics` (request count, latency) | `:8000/metrics` | ServiceMonitor |
| LiveKit server | Rooms, participants, quality scores | `:6789/metrics` | Pod annotation |
| LiveKit egress | Active jobs, uploads | `:6789/metrics` | Pod annotation |

#### What is a ServiceMonitor?

A Custom Resource (CRD) that tells Prometheus "scrape these pods on this port/path at this interval". It replaces static scrape configs — Prometheus auto-discovers targets via label selectors. Example:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: convogent-backend
spec:
  selector:
    matchLabels:
      app: convogent-backend
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
```

---

### 2. GRAFANA (Visualization)

**What it does:** Dashboard UI for metrics, logs, and traces. Queries Prometheus/Loki/Tempo and displays results in panels.

#### Containers

| Container | Image | Tag | Role |
|-----------|-------|-----|------|
| Main | `grafana` | `12.0.0` | Web UI + query engine |
| Init | `busybox` | `1.31.1` | `init-chown-data` — sets file permissions on PVC before Grafana starts |
| Sidecar | `k8s-sidecar` | `1.30.0` | Watches ConfigMaps with label `grafana_dashboard=1` and auto-loads dashboards |

#### Deployment Details

| Property | Value |
|----------|-------|
| Deployed as | Deployment (1 replica) |
| PVC | 5Gi gp3 (dashboard DB, plugin storage, sessions) |
| Endpoint | `prometheus-grafana.monitoring.svc.cluster.local:80` |

#### Datasources Configured

| Name | Type | Internal URL |
|------|------|-------------|
| Prometheus | Metrics (PromQL) | `http://prometheus-prometheus.monitoring.svc.cluster.local:9090` |
| Loki | Logs (LogQL) | `http://loki-gateway.monitoring.svc.cluster.local` |
| Tempo | Traces (TraceQL) | `http://tempo-query-frontend.monitoring.svc.cluster.local:3200` |

#### How the Sidecar Works

Any ConfigMap in any namespace with label `grafana_dashboard: "1"` gets automatically loaded as a Grafana dashboard JSON. No manual import needed — just create a ConfigMap with dashboard JSON and it appears in Grafana.

---

### 3. LOKI (Logs)

**What it does:** Receives, indexes, and stores logs. Queryable via LogQL from Grafana. Like Prometheus but for logs.

#### Containers

| Container | Image | Tag | Role |
|-----------|-------|-----|------|
| Main | `loki` | `3.3.2` | Log ingestion + storage + query engine |
| Gateway | `nginx-unprivileged` | `1.27-alpine` | Reverse proxy for routing and load balancing |
| Sidecar | `k8s-sidecar` | `1.30.0` | Syncs alerting/recording rules from ConfigMaps |

#### Deployment Details

| Property | Value |
|----------|-------|
| Deployed as | StatefulSet (SingleBinary mode, 1 replica) + Deployment (gateway) |
| PVC | 20Gi gp3 (chunks + WAL + index on local filesystem) |
| Retention | 7 days |
| Endpoint | `loki-gateway.monitoring.svc.cluster.local:80` |

#### How Loki Gets Logs

Loki does NOT pull logs. The OTel Collector pushes logs to it:

```
Pod stdout/stderr
    → containerd writes to /var/log/pods/<ns>_<pod>_<uid>/<container>/*.log
        → OTel Collector (DaemonSet) tails the file
            → Enriches with K8s metadata (namespace, pod, deployment)
                → Pushes to Loki via HTTP POST /loki/api/v1/push
```

---

### 4. TEMPO (Traces)

**What it does:** Receives, stores, and queries distributed traces (spans). Uses S3 for durable long-term storage.

#### Containers (all use same image, different entrypoint args)

| Container | Image | Tag | Role |
|-----------|-------|-----|------|
| Distributor | `tempo` | `2.9.0` | Receives OTLP traces, hashes trace IDs, routes to correct ingester |
| Ingester | `tempo` | `2.9.0` | Writes traces to WAL (Write Ahead Log), flushes blocks to S3 |
| Querier | `tempo` | `2.9.0` | Reads traces from ingesters (recent) + S3 (historical) |
| Query Frontend | `tempo` | `2.9.0` | Splits large queries, caches results, serves Grafana |
| Compactor | `tempo` | `2.9.0` | Compacts small blocks in S3 into larger ones, enforces retention |

#### Deployment Details

| Property | Value |
|----------|-------|
| Deployed as | 5 separate Deployments (1 replica each) |
| PVC | 10Gi gp3 (ingester WAL only) |
| S3 Storage | `<S3_TRACES_BUCKET>` in ap-south-1 |
| Retention | 30 days |
| Endpoint | `tempo-distributor.monitoring.svc.cluster.local:4317` (OTLP gRPC) |
| Query Endpoint | `tempo-query-frontend.monitoring.svc.cluster.local:3200` (Grafana) |

#### How Tempo Gets Traces

Apps must be instrumented with OpenTelemetry SDK. They send spans via OTLP:

```
App code (instrumented with OTel SDK)
    → Sets env vars:
        ENABLE_TRACING=true
        OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4317
        OTEL_SERVICE_NAME=convogent-backend
    → Sends spans via gRPC to OTel Collector
        → OTel Collector enriches with K8s metadata
            → Forwards to Tempo Distributor
                → Ingester writes to WAL → flushes to S3
```

Which apps send traces:
- `convogent-backend` (OTEL_SERVICE_NAME: convogent-backend)
- `convogent-voice` (OTEL_SERVICE_NAME: convogent-voice)

---

### 5. OTEL COLLECTOR (Pipeline — Glue Layer)

**What it does:** Collects logs from all pod files on every node + receives OTLP traces from apps. Enriches everything with Kubernetes metadata. Routes to Loki (logs) and Tempo (traces).

#### Containers

| Container | Image | Tag | Role |
|-----------|-------|-----|------|
| Main | `otel-collector-contrib` | `0.118.0` | All-in-one: filelog receiver + OTLP receiver + K8s enrichment + exporters |

#### Deployment Details

| Property | Value |
|----------|-------|
| Deployed as | DaemonSet (1 pod per node, runs on ALL nodes) |
| PVC | None |
| Host volumes | `/var/log/pods` + `/var/log/containers` (read-only, for log tailing) |
| Tolerations | `operator: Exists` (runs on tainted nodes too: app, voice, livekit, monitoring) |
| OTLP Endpoint | `otel-collector-opentelemetry-collector.monitoring.svc.cluster.local:4317` |

#### Pipelines

| Pipeline | Receiver | Processing | Exporter |
|----------|----------|-----------|----------|
| **Logs** | `filelog` (tails /var/log/pods/* on each node) | Parse containerd log format → Extract K8s metadata from file path → Enrich via k8sattributes API (deployment name, labels) → Derive service.name → Add cluster label | Push to Loki |
| **Traces** | `otlp` (gRPC :4317 + HTTP :4318 from apps) | Enrich via k8sattributes → Add cluster label → Batch | Push to Tempo |

---

### 6. SUPPORTING COMPONENTS

#### Prometheus Operator — "The Manager"

| | |
|-|-|
| Image | `prometheus-operator:v0.82.0` |
| Deployed as | Deployment (1 replica) |
| PVC | None |
| What it does | Watches CRDs (ServiceMonitor, PrometheusRule, Alertmanager) and auto-configures Prometheus scrape targets |
| Why needed | Without it, you'd manually edit prometheus.yml every time you add/remove a service. With operator, just create a ServiceMonitor CR |
| Can Prometheus run without it? | Yes, but you'd manage static configs manually |

#### Alertmanager — "The Notification Router"

| | |
|-|-|
| Image | `alertmanager:v0.28.1` + sidecar `prometheus-config-reloader:v0.82.0` |
| Deployed as | StatefulSet (1 replica) |
| PVC | 2Gi gp3 |
| What it does | Receives alerts from Prometheus, deduplicates, groups, silences, routes to Slack/email/PagerDuty |
| Why needed | Prometheus fires alerts but can't send notifications |
| Can Prometheus run without it? | Yes, alerts fire but go nowhere |

#### kube-state-metrics — "The K8s Object Reporter"

| | |
|-|-|
| Image | `kube-state-metrics:v2.15.0` |
| Deployed as | Deployment (1 replica) |
| PVC | None |
| What it does | Watches K8s API and generates metrics about object STATE (not resource usage) |
| Examples | "Deployment X wants 3 replicas but only 2 ready", "Pod Y in CrashLoopBackOff", "HPA Z at max replicas", "PVC 90% full" |
| Why needed | kubelet/cAdvisor gives resource USAGE. kube-state-metrics gives object HEALTH |
| Can Prometheus run without it? | Yes, but you lose visibility into K8s object state |

#### Node Exporter — "The Host Spy"

| | |
|-|-|
| Image | `node-exporter:v1.9.1` |
| Deployed as | DaemonSet (runs on ALL nodes) |
| PVC | None |
| What it does | Exposes host-level metrics: bare-metal CPU, memory, disk space, filesystem, network interfaces, system load |
| Why needed | Container metrics (cAdvisor) show per-pod usage. Node Exporter shows the HOST — disk full? NIC errors? System overloaded? |
| Can Prometheus run without it? | Yes, but no host-level visibility |
| Tolerations | `operator: Exists` (runs on all tainted nodes) |

#### Prometheus Adapter — "The HPA Bridge"

| | |
|-|-|
| Image | `prometheus-adapter:v0.12.0` |
| Deployed as | Deployment (1 replica) |
| PVC | None |
| What it does | Bridges Prometheus metrics into the K8s custom metrics API so HPA can use them |
| Why needed | HPA only reads from K8s Metrics API. Standard metrics-server gives CPU/memory. For custom metrics (like `livekit_egress_requests`), adapter translates PromQL → Metrics API |
| Can Prometheus run without it? | Yes, but custom metric HPAs won't work |
| How it works | HPA → K8s custom metrics API → Adapter → queries Prometheus → returns value → HPA scales |

---

## What's Required vs Nice-to-Have

| Component | Required? | Without it |
|-----------|-----------|------------|
| **Prometheus Server** | ✅ Must have | No metrics at all |
| **OTel Collector** | ✅ Must have | No logs in Loki, no traces in Tempo |
| **Grafana** | ✅ Must have | No dashboards/visualization |
| **Loki** | ✅ For logs | No log aggregation |
| **Tempo** | ✅ For traces | No distributed tracing |
| **Prometheus Operator** | Recommended | Manual scrape config management |
| **Config Reloader** | Recommended | Restart pod on every config change |
| **Node Exporter** | Recommended | No host-level metrics |
| **kube-state-metrics** | Recommended | No K8s object health metrics |
| **Alertmanager** | Nice to have | Alerts fire but no notifications |
| **Prometheus Adapter** | Only if custom HPA | LiveKit egress HPA won't work |

---

## Communication Map

```
┌─────────────────────────────────────────────────────────────┐
│                  HOW COMPONENTS TALK                          │
│                                                             │
│  Prometheus Operator                                         │
│       │ watches ServiceMonitor CRDs                          │
│       │ manages Prometheus config                            │
│       ▼                                                      │
│  Prometheus Server                                           │
│       │ scrapes targets (HTTP GET /metrics every 15-30s)     │
│       │ stores in TSDB (PVC)                                 │
│       │                                                      │
│       ├──► fires alerts ──► Alertmanager ──► (notifications) │
│       │                                                      │
│       ├──◄── Grafana queries (PromQL over HTTP :9090)        │
│       │                                                      │
│       └──◄── Prometheus Adapter queries (for HPA)            │
│                                                             │
│  OTel Collector (DaemonSet on every node)                    │
│       │                                                      │
│       ├── tails /var/log/pods/* ──► pushes to Loki           │
│       │                                                      │
│       └── receives OTLP from apps ──► pushes to Tempo        │
│                                                             │
│  Grafana                                                     │
│       ├── queries Prometheus (metrics)                        │
│       ├── queries Loki (logs)                                │
│       └── queries Tempo (traces)                             │
│                                                             │
│  Node Exporter (DaemonSet)                                   │
│       └── exposes :9100/metrics ──► Prometheus scrapes it    │
│                                                             │
│  kube-state-metrics (Deployment)                             │
│       └── watches K8s API, exposes :8080/metrics             │
│           ──► Prometheus scrapes it                           │
└─────────────────────────────────────────────────────────────┘
```

---

## Images Summary (for bank ECR)

| # | ECR Repo | Tag | Used By | Container Type |
|---|----------|-----|---------|----------------|
| 1 | `prometheus` | `v3.3.1` | Prometheus | Main |
| 2 | `prometheus-operator` | `v0.82.0` | Prometheus Operator | Main |
| 3 | `prometheus-config-reloader` | `v0.82.0` | Prometheus + Alertmanager | Sidecar |
| 4 | `alertmanager` | `v0.28.1` | Alertmanager | Main |
| 5 | `grafana` | `12.0.0` | Grafana | Main |
| 6 | `k8s-sidecar` | `1.30.0` | Grafana + Loki | Sidecar |
| 7 | `busybox` | `1.31.1` | Grafana | Init container |
| 8 | `node-exporter` | `v1.9.1` | Node Exporter | Main (DaemonSet) |
| 9 | `kube-state-metrics` | `v2.15.0` | kube-state-metrics | Main |
| 10 | `loki` | `3.3.2` | Loki | Main |
| 11 | `nginx-unprivileged` | `1.27-alpine` | Loki Gateway | Main |
| 12 | `tempo` | `2.9.0` | Tempo (all 5 components) | Main |
| 13 | `otel-collector-contrib` | `0.118.0` | OTel Collector | Main (DaemonSet) |
| 14 | `prometheus-adapter` | `v0.12.0` | Prometheus Adapter | Main |

---

## PVC Summary

| Component | Size | StorageClass | What's stored |
|-----------|------|-------------|---------------|
| Prometheus | 20Gi | gp3 | TSDB (time-series data, 7 day retention) |
| Grafana | 5Gi | gp3 | SQLite DB (dashboards, users, sessions) |
| Loki | 20Gi | gp3 | Log chunks + WAL + TSDB index |
| Tempo Ingester | 10Gi | gp3 | Write Ahead Log (before flushing to S3) |
| Alertmanager | 2Gi | gp3 | Silence state + notification log |
| **Total** | **57Gi** | | |


---

## How Prometheus Operator, Alertmanager & Adapter are Coupled

---

### Prometheus Operator ↔ Prometheus Server

The Operator is a controller that watches CRDs (ServiceMonitor, PrometheusRule) and auto-generates Prometheus scrape config.

**Flow when you create a ServiceMonitor:**

```
1. You create ServiceMonitor CR (kubectl apply)
        │
        ▼
2. Prometheus Operator (watching K8s API for ServiceMonitor resources)
        │
        │ Reads the ServiceMonitor spec (selector, port, path, interval)
        │ Generates a scrape config snippet
        │ Merges ALL ServiceMonitors into one config
        │ Writes to a Kubernetes Secret
        ▼
3. Secret: prometheus-prometheus-scrape-config
   (mounted as volume in Prometheus pod)
        │
        ▼
4. kubelet updates the mounted file inside the pod
        │
        ▼
5. Config Reloader sidecar (watches the file via inotify)
        │
        │ Detects file changed → sends HTTP POST localhost:9090/-/reload
        ▼
6. Prometheus Server reloads config (hot reload, no restart)
        │
        │ Now scrapes the new target
        ▼
7. Scrapes http://convogent-backend:8000/metrics every 30s
```

**Key points:**
- Operator writes ALL ServiceMonitors into ONE Secret (not one per ServiceMonitor)
- Prometheus never talks to the Operator directly — it just reads a config file
- Config Reloader uses filesystem inotify to detect changes (not K8s API watch)
- Reload is a hot reload via HTTP — no pod restart needed

---

### Alertmanager ↔ Prometheus Server

Prometheus evaluates alerting rules and PUSHES firing alerts to Alertmanager.

**How they're connected:**

Prometheus config (auto-generated by Operator) contains:
```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager-operated.monitoring.svc.cluster.local:9093
```

**Flow:**

```
1. You create a PrometheusRule CR:
   
   rules:
     - alert: HighCPU
       expr: container_cpu_usage > 0.9
       for: 5m
       labels:
         severity: critical

2. Operator renders it into a ConfigMap → mounted into Prometheus at /etc/prometheus/rules/

3. Prometheus evaluates the rule every 15s:
   "Is container_cpu_usage > 0.9 for 5 minutes?"
   
   If YES → alert state = FIRING

4. Prometheus PUSHES the firing alert to Alertmanager:
   HTTP POST http://alertmanager:9093/api/v2/alerts
   Body: { alertname: "HighCPU", severity: "critical", pod: "backend-xyz" }

5. Alertmanager receives and:
   - Deduplicates (same alert from multiple Prometheus replicas)
   - Groups (batches related alerts together)
   - Waits (group_wait: 30s before first notification)
   - Routes to receiver (Slack, email, PagerDuty based on labels)
   - Handles silences and inhibition
```

**Key point:** Prometheus pushes TO Alertmanager. Alertmanager never pulls.

---

### Prometheus Adapter ↔ Prometheus Server

The Adapter bridges Prometheus metrics into the K8s custom metrics API for HPA.

**The problem:** HPA can only read from K8s Metrics API. It cannot query Prometheus directly.

**How they're connected:**

Adapter config points to Prometheus:
```yaml
prometheus:
  url: http://prometheus-prometheus.monitoring.svc.cluster.local
  port: 9090
```

**Flow:**

```
1. HPA is configured:
   metrics:
     - type: Pods
       pods:
         metric:
           name: livekit_egress_requests
         target:
           averageValue: "18"

2. Every 15s, HPA controller asks K8s API:
   GET /apis/custom.metrics.k8s.io/v1beta1/namespaces/livekit/pods/*/livekit_egress_requests

3. K8s API Server routes to Prometheus Adapter (registered as APIService)

4. Adapter translates into PromQL:
   sum(livekit_egress_requests{namespace="livekit"}) by (pod)

5. Adapter queries Prometheus:
   GET http://prometheus:9090/api/v1/query?query=...

6. Prometheus returns: { pod-1: 20, pod-2: 15, pod-3: 22 }

7. Adapter formats as K8s Metrics API response → returns to HPA

8. HPA calculates: average = 19, target = 18 → scale up
```

**Key point:** Adapter pulls FROM Prometheus. Prometheus doesn't know the Adapter exists — it's just another PromQL client.

---

## Push vs Pull — Complete Map

### Metrics (Prometheus ecosystem)

| From | To | Mechanism | Who initiates | Detail |
|------|----|-----------|---------------|--------|
| Node Exporter | Prometheus | **Pull** | Prometheus scrapes `:9100/metrics` every 30s |
| kube-state-metrics | Prometheus | **Pull** | Prometheus scrapes `:8080/metrics` every 30s |
| kubelet/cAdvisor | Prometheus | **Pull** | Prometheus scrapes `:10250/metrics/cadvisor` every 30s |
| kube-apiserver | Prometheus | **Pull** | Prometheus scrapes `:6443/metrics` every 30s |
| CoreDNS | Prometheus | **Pull** | Prometheus scrapes `:9153/metrics` every 30s |
| App pods (`/metrics`) | Prometheus | **Pull** | Prometheus scrapes based on ServiceMonitor |
| LiveKit server/egress | Prometheus | **Pull** | Prometheus scrapes `:6789/metrics` (pod annotation) |
| Prometheus | Alertmanager | **Push** | Prometheus pushes firing alerts to `:9093` |
| Prometheus | Prometheus Adapter | **Pull** | Adapter queries Prometheus on HPA request |

### Logs (Loki ecosystem)

| From | To | Mechanism | Who initiates | Detail |
|------|----|-----------|---------------|--------|
| Pod logs on disk | OTel Collector | **Pull** (file tail) | OTel tails `/var/log/pods/*` using inotify |
| OTel Collector | Loki | **Push** | OTel pushes via `POST /loki/api/v1/push` |
| Grafana | Loki | **Pull** | Grafana queries via LogQL on user request |

### Traces (Tempo ecosystem)

| From | To | Mechanism | Who initiates | Detail |
|------|----|-----------|---------------|--------|
| App code (OTel SDK) | OTel Collector | **Push** | App pushes spans via OTLP gRPC `:4317` |
| OTel Collector | Tempo Distributor | **Push** | OTel forwards spans via OTLP gRPC |
| Tempo Ingester | S3 | **Push** | Ingester flushes blocks to S3 periodically |
| Grafana | Tempo Query Frontend | **Pull** | Grafana queries traces by ID on user request |

### Management / Config

| From | To | Mechanism | Who initiates | Detail |
|------|----|-----------|---------------|--------|
| Prometheus Operator | Prometheus (Secret) | **Push** | Operator writes config on ServiceMonitor change |
| Config Reloader | Prometheus | **Push** (reload signal) | Reloader sends `/-/reload` on file change |
| k8s-sidecar | Grafana | **Push** (file sync) | Sidecar writes dashboard JSON into provisioning dir |
| HPA | Prometheus Adapter | **Pull** | HPA queries custom metrics API every 15s |
| Prometheus Adapter | Prometheus | **Pull** | Adapter queries PromQL to answer HPA |

### Summary by signal type

| Signal | Collection model | Why |
|--------|-----------------|-----|
| **Metrics** | Pull (Prometheus scrapes targets) | Prometheus controls timing, handles target failures gracefully |
| **Logs** | Pull + Push (OTel tails files, then pushes to Loki) | Can't scrape logs — must tail files, then ship |
| **Traces** | Push (apps → collector → Tempo) | Only the app knows when a span starts/ends |
| **Alerts** | Push (Prometheus → Alertmanager) | Prometheus evaluates rules, pushes only when firing |

---

## Complete Communication Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  Prometheus Operator                                                 │
│       │ watches ServiceMonitor/PrometheusRule CRDs                    │
│       │ writes config to Secret (one Secret, all jobs merged)        │
│       ▼                                                              │
│  ┌─────────────────────────────────────────────────────────────┐     │
│  │ Prometheus Pod                                               │     │
│  │  ┌─────────────────┐   ┌──────────────────────────────┐     │     │
│  │  │ prometheus       │   │ config-reloader (sidecar)    │     │     │
│  │  │                  │   │                              │     │     │
│  │  │ ◄─reload─────────│───│ watches /etc/prometheus/     │     │     │
│  │  │                  │   │ via inotify                  │     │     │
│  │  │ scrapes targets  │   └──────────────────────────────┘     │     │
│  │  │ evaluates rules  │                                        │     │
│  │  │ stores TSDB      │                                        │     │
│  │  └────────┬─────────┘                                        │     │
│  └───────────┼──────────────────────────────────────────────────┘     │
│              │                                                        │
│    ┌─────────┼──────────────────────────────────────────┐            │
│    │         │ PULL (scrapes every 15-30s)               │            │
│    │         ├──► Node Exporter (DaemonSet) :9100        │            │
│    │         ├──► kube-state-metrics :8080               │            │
│    │         ├──► kubelet/cAdvisor :10250                │            │
│    │         ├──► kube-apiserver :6443                   │            │
│    │         ├──► CoreDNS :9153                          │            │
│    │         ├──► Convogent backend :8000/metrics        │            │
│    │         └──► LiveKit server/egress :6789            │            │
│    └────────────────────────────────────────────────────┘            │
│              │                                                        │
│              │ PUSH (alerts)                                          │
│              ▼                                                        │
│  ┌──────────────────┐                                                │
│  │ Alertmanager      │──notify──► Slack / Email / PagerDuty          │
│  └──────────────────┘                                                │
│              ▲                                                        │
│              │ PULL (queries)                                         │
│  ┌───────────┴──────────┐                                            │
│  │ Prometheus Adapter    │◄──── HPA queries custom metrics API       │
│  └──────────────────────┘                                            │
│              ▲                                                        │
│              │ PULL (queries: PromQL, LogQL, TraceQL)                 │
│  ┌───────────┴──────────┐                                            │
│  │ Grafana               │ (dashboards for humans)                   │
│  └───────────┬───────────┘                                            │
│              │ also queries:                                          │
│              ├──► Loki (logs)                                         │
│              └──► Tempo (traces)                                      │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │ OTel Collector (DaemonSet — every node)                       │    │
│  │                                                              │    │
│  │  Logs pipeline:                                              │    │
│  │    tails /var/log/pods/* ──► enriches ──► PUSH to Loki       │    │
│  │                                                              │    │
│  │  Traces pipeline:                                            │    │
│  │    receives OTLP from apps ──► enriches ──► PUSH to Tempo    │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                        ▲                                             │
│                        │ PUSH (OTLP gRPC :4317)                      │
│               ┌────────┴─────────┐                                   │
│               │ App pods          │                                   │
│               │ (backend, voice)  │                                   │
│               │ instrumented with │                                   │
│               │ OTel SDK          │                                   │
│               └──────────────────┘                                   │
└─────────────────────────────────────────────────────────────────────┘
```
