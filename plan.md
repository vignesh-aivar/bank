# Infrastructure Node Placement Plan — Convogent V2 (Bank EKS)

## Cluster Overview

| Layer | Type | Purpose |
|-------|------|---------|
| Core Node Group | EKS Managed (self-managed) | Karpenter controller, KEDA operator, CoreDNS, kube-system |
| Karpenter NodePools | Auto-provisioned | Application workloads, LiveKit, Monitoring, Voice agents |

---

## Node Groups & NodePools Summary

### 1. Managed Node Group (EKS-managed — always running)

| Name | Purpose | Nodes | Instance Type | Taints |
|------|---------|-------|---------------|--------|
| **core** | Cluster infra (Karpenter, KEDA, CoreDNS, ArgoCD) | 1 | Managed by EKS | None (system workloads) |

**Services on core:**
- Karpenter controller
- KEDA operator + metrics-apiserver + admission-webhooks
- CoreDNS, kube-proxy, aws-node (VPC CNI)
- ArgoCD (if deployed)

---

### 2. Karpenter NodePools (auto-provisioned on demand)

| # | NodePool Name | NodeClass | Services | Instance Family | Arch | Capacity | AZ Pinned | Taint Key=Value |
|---|---------------|-----------|----------|-----------------|------|----------|-----------|-----------------|
| 1 | **agent-voice** | default | convogent-voice-service (ISOLATED) | c6in, c5n, c6a, c6i | amd64 | spot + on-demand | No | `workload=agent-voice:NoSchedule` |
| 2 | **dev-workloads** | default | frontend, backend, chat, eval, pca (SHARED) | c6in, c5n, m6in, c6a, c6i, m6a, m6i | amd64 | spot + on-demand | No | `workload=dev-workloads:NoSchedule` |
| 3 | **monitoring** | default | Prometheus, Grafana, Loki, Tempo, Alertmanager, kube-state-metrics, prometheus-adapter | t4g, m7g | arm64 | on-demand | ap-south-1b | `workload=monitoring:NoSchedule` |
| 4 | **livekit-server** | livekit-private | LiveKit SFU server | c7g.xlarge, c7g.2xlarge | arm64 | on-demand | ap-south-1a | `workload=livekit-server:NoSchedule` |
| 5 | **livekit-sip** | livekit-public | LiveKit SIP bridge (hostNetwork) | c7g.xlarge | arm64 | on-demand | ap-south-1a | `workload=livekit-sip:NoSchedule` |
| 6 | **livekit-egress** | livekit-egress | LiveKit egress (recording/streaming) | c7g.2xlarge | arm64 | on-demand | ap-south-1a | `workload=livekit-egress:NoSchedule` |

---

## Node Class Details

| NodeClass | Subnets | Public IP | Security Groups | Role |
|-----------|---------|-----------|-----------------|------|
| **default** | Private (internal-elb tagged) | No | Cluster SG | convogent-v2-loadtest-karpenter-node |
| **livekit-private** | Private (internal-elb tagged) | No | Cluster SG + LiveKit media SG | convogent-v2-loadtest-karpenter-node |
| **livekit-public** | Public (elb tagged) | **Yes** | Cluster SG + LiveKit media SG | convogent-v2-loadtest-karpenter-node |
| **livekit-egress** | Private (internal-elb tagged) | No | Cluster SG + LiveKit media SG | convogent-v2-loadtest-karpenter-node |

---

## Service → NodePool Mapping

### Application Services (charts/)

| Service | NodePool | nodeSelector | Toleration | KEDA Enabled | Scaling Triggers |
|---------|----------|--------------|------------|--------------|------------------|
| **convogent-voice-service** | agent-voice | `NodeGroupType: agent-voice` | `workload=agent-voice:NoSchedule` | Yes | CPU 70%, Memory 70% |
| **convogent-backend** | dev-workloads | `NodeGroupType: dev-workloads` | `workload=dev-workloads:NoSchedule` | Yes | CPU 60%, Memory 70% |
| **convogent-frontend** | dev-workloads | `NodeGroupType: dev-workloads` | `workload=dev-workloads:NoSchedule` | Yes | CPU 60%, Memory 70% |
| **convogent-chat-service** | dev-workloads | `NodeGroupType: dev-workloads` | `workload=dev-workloads:NoSchedule` | Yes | CPU 65%, Memory 75% |
| **convogent-eval-service** | dev-workloads | `NodeGroupType: dev-workloads` | `workload=dev-workloads:NoSchedule` | Yes | CPU 65%, Memory 75% |
| **convogent-pca-service** | dev-workloads | `NodeGroupType: dev-workloads` | `workload=dev-workloads:NoSchedule` | Yes | CPU 65%, Memory 75% |

### LiveKit Services (addons/livekit/)

| Service | NodePool | nodeSelector | Toleration | Scaling |
|---------|----------|--------------|------------|---------|
| **livekit-server** | livekit-server | `workload: livekit-server` | `workload=livekit-server:NoSchedule` | HPA: min 3, max 10, CPU 60% |
| **livekit-sip** | livekit-sip | `workload: livekit-sip` | `workload=livekit-sip:NoSchedule` | Manual (replicas in manifest) |
| **livekit-egress** | livekit-egress | `workload: livekit-egress` | `workload=livekit-egress:NoSchedule` | HPA: min 5, max 30, CPU 60% |

### Monitoring Services (addons/monitoring/)

| Service | NodePool | nodeSelector | Toleration |
|---------|----------|--------------|------------|
| **Prometheus** | monitoring | `NodeGroupType: monitoring` | `workload=monitoring:NoSchedule` |
| **Grafana** | monitoring | `NodeGroupType: monitoring` | `workload=monitoring:NoSchedule` |
| **Alertmanager** | monitoring | `NodeGroupType: monitoring` | `workload=monitoring:NoSchedule` |
| **Loki** | monitoring | `NodeGroupType: monitoring` | `workload=monitoring:NoSchedule` |
| **Tempo** (all components) | monitoring | `NodeGroupType: monitoring` | `workload=monitoring:NoSchedule` |
| **kube-state-metrics** | monitoring | `NodeGroupType: monitoring` | `workload=monitoring:NoSchedule` |
| **prometheus-adapter** | monitoring | `NodeGroupType: monitoring` | `workload=monitoring:NoSchedule` |
| **node-exporter** | ALL nodes (DaemonSet) | — | `operator: Exists` |
| **otel-collector** | ALL nodes (DaemonSet) | — | `operator: Exists` |

### Cluster Infrastructure (core managed node group)

| Service | Where | nodeSelector | Toleration |
|---------|-------|--------------|------------|
| **Karpenter** | core | `NodeGroupType: core` | None |
| **KEDA** | core | `NodeGroupType: core` | None |
| **CoreDNS** | core | — | System tolerations |

---

## Disruption Policies

| NodePool | Policy | ConsolidateAfter | Rationale |
|----------|--------|------------------|-----------|
| agent-voice | WhenEmptyOrUnderutilized | 1m | Long-lived voice calls, but pods can migrate between calls |
| dev-workloads | WhenEmptyOrUnderutilized | 30s | Stateless services, fast scale-down OK |
| monitoring | WhenEmptyOrUnderutilized | 5m | PVCs make moves slow, moderate cooldown |
| livekit-server | WhenEmptyOrUnderutilized | 15m | SFU state lost on eviction, careful with consolidation |
| livekit-sip | WhenEmptyOrUnderutilized | 30m | Active SIP sessions cannot survive node replacement |
| livekit-egress | **WhenEmpty** | 5m | Recording jobs are LOST on interruption — never consolidate underutilized |

---

## Resource Limits per NodePool

| NodePool | CPU Limit | Memory Limit | Max Instance Size |
|----------|-----------|--------------|-------------------|
| agent-voice | 128 vCPU | 256Gi | xlarge |
| dev-workloads | 96 vCPU | 192Gi | large, xlarge, 2xlarge |
| monitoring | 8 vCPU | 16Gi | large |
| livekit-server | 100 vCPU | 200Gi | xlarge, 2xlarge |
| livekit-sip | 100 vCPU | 200Gi | xlarge |
| livekit-egress | 100 vCPU | 200Gi | 2xlarge |

---

## Key Differences from Reference Repo (aivar-convogent-load-test feat/loadtest)

| Config | Reference Repo | Our Repo | Status |
|--------|---------------|----------|--------|
| NodePool name for shared services | `dev-workloads` | `dev-workloads` | ✅ FIXED |
| Taint value for shared services | `dev-workloads` | `dev-workloads` | ✅ FIXED |
| Label for shared services | `NodeGroupType: dev-workloads` | `NodeGroupType: dev-workloads` | ✅ FIXED |
| Monitoring nodepool | Present | Present | ✅ FIXED |
| agent-voice instance family | c6in, c5n, c6a, c6i | c6in, c5n, c6a, c6i | ✅ FIXED |
| agent-voice instance size | xlarge only | xlarge only | ✅ FIXED |
| livekit-egress capacity type | on-demand only | on-demand only | ✅ FIXED |
| livekit-egress disruption | WhenEmpty | WhenEmpty | ✅ FIXED |
| livekit-egress instance type | c7g.2xlarge only | c7g.2xlarge only | ✅ FIXED |
| livekit-server AZ pin | NOT pinned | ap-south-1a | ✅ Intentional (our cluster needs intra-AZ) |
| KEDA nodeSelector | `NodeGroupType: core` | `NodeGroupType: core` | ✅ FIXED |
| Karpenter nodeSelector | `NodeGroupType: core` | N/A (EKS managed) | ✅ N/A |

---

## Visual Node Layout

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         EKS CLUSTER                                      │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────────────┐  MANAGED NODE GROUP (always on)               │
│  │     CORE NODE        │                                                │
│  │  ┌────────────────┐  │                                                │
│  │  │ Karpenter      │  │                                                │
│  │  │ KEDA           │  │                                                │
│  │  │ CoreDNS        │  │                                                │
│  │  │ ArgoCD         │  │                                                │
│  │  └────────────────┘  │                                                │
│  └──────────────────────┘                                                │
│                                                                          │
│  ┌──────────────────────┐  KARPENTER: agent-voice                        │
│  │  VOICE NODES (amd64) │  Taint: workload=agent-voice                   │
│  │  c6in/c5n.xlarge     │                                                │
│  │  ┌────────────────┐  │                                                │
│  │  │ voice-service  │  │  ← ISOLATED (only service on this nodepool)    │
│  │  │ voice-service  │  │                                                │
│  │  │ voice-service  │  │                                                │
│  │  └────────────────┘  │                                                │
│  └──────────────────────┘                                                │
│                                                                          │
│  ┌──────────────────────┐  KARPENTER: dev-workloads                      │
│  │  APP NODES (amd64)   │  Taint: workload=dev-workloads                 │
│  │  c6in/c6a/m6a etc.   │                                                │
│  │  ┌────────────────┐  │                                                │
│  │  │ frontend       │  │                                                │
│  │  │ backend        │  │  ← 5 services BIN-PACKED together              │
│  │  │ chat-service   │  │                                                │
│  │  │ eval-service   │  │                                                │
│  │  │ pca-service    │  │                                                │
│  │  └────────────────┘  │                                                │
│  └──────────────────────┘                                                │
│                                                                          │
│  ┌──────────────────────┐  KARPENTER: monitoring (ap-south-1b)           │
│  │  MONITORING (arm64)  │  Taint: workload=monitoring                    │
│  │  t4g/m7g.large       │                                                │
│  │  ┌────────────────┐  │                                                │
│  │  │ Prometheus     │  │                                                │
│  │  │ Grafana        │  │                                                │
│  │  │ Loki           │  │                                                │
│  │  │ Tempo          │  │                                                │
│  │  │ Alertmanager   │  │                                                │
│  │  └────────────────┘  │                                                │
│  └──────────────────────┘                                                │
│                                                                          │
│  ┌──────────────────────┐  KARPENTER: livekit-server (ap-south-1a)       │
│  │  LK SERVER (arm64)   │  Taint: workload=livekit-server                │
│  │  c7g.xlarge/2xlarge  │                                                │
│  │  ┌────────────────┐  │                                                │
│  │  │ livekit-server │  │  ← SFU media routing                          │
│  │  └────────────────┘  │                                                │
│  └──────────────────────┘                                                │
│                                                                          │
│  ┌──────────────────────┐  KARPENTER: livekit-sip (ap-south-1a)          │
│  │  LK SIP (arm64)     │  Taint: workload=livekit-sip                   │
│  │  c7g.xlarge PUBLIC   │                                                │
│  │  ┌────────────────┐  │                                                │
│  │  │ livekit-sip    │  │  ← hostNetwork, public IP for PSTN RTP        │
│  │  └────────────────┘  │                                                │
│  └──────────────────────┘                                                │
│                                                                          │
│  ┌──────────────────────┐  KARPENTER: livekit-egress (ap-south-1a)       │
│  │  LK EGRESS (arm64)  │  Taint: workload=livekit-egress                │
│  │  c7g.2xlarge ON-DEM  │                                                │
│  │  ┌────────────────┐  │                                                │
│  │  │ livekit-egress │  │  ← recording/streaming, NO SPOT               │
│  │  └────────────────┘  │                                                │
│  └──────────────────────┘                                                │
│                                                                          │
│  ┌──────────────────────┐  DAEMONSETS (run on ALL nodes)                 │
│  │  otel-collector      │  tolerations: [{operator: Exists}]             │
│  │  node-exporter       │  tolerations: [{operator: Exists}]             │
│  └──────────────────────┘                                                │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## KEDA Configuration

- **Deployed to:** core managed node group (`NodeGroupType: core`)
- **Images:** Public ECR (`public.ecr.aws/u7h9i3k7/keda/*:2.20.2`)
- **Components:** operator, metrics-apiserver, admission-webhooks
- **Scaling targets:**
  - convogent-voice-service (CPU 70%)
  - convogent-backend (CPU 60%)
  - convogent-frontend (CPU 60%)
  - convogent-chat-service (CPU 65%)
  - convogent-eval-service (CPU 65%)
  - convogent-pca-service (CPU 65%)
- **Reference repo version:** KEDA 2.16.1 (our repo: 2.20.2 — newer is fine)

---

## Pod Counts per Service

### Application Services (KEDA-managed)

| Service | NodePool | Min Replicas | Max Replicas | Steady-State Pods | Resources per Pod |
|---------|----------|--------------|--------------|-------------------|-------------------|
| **convogent-voice-service** | agent-voice | 1 | 20 | 2-5 | 2 CPU / 2.5Gi req → 4 CPU / 4Gi lim |
| **convogent-backend** | dev-workloads | 1 | 6 | 1-2 | 100m CPU / 512Mi req → 500m / 1Gi lim |
| **convogent-frontend** | dev-workloads | 1 | 3 | 1 | 50m CPU / 64Mi req → 200m / 128Mi lim |
| **convogent-chat-service** | dev-workloads | 1 | 5 | 1-2 | 200m CPU / 384Mi req → 500m / 768Mi lim |
| **convogent-eval-service** | dev-workloads | 1 | 5 | 1-2 | 150m CPU / 192Mi req → 500m / 512Mi lim |
| **convogent-pca-service** | dev-workloads | 1 | 5 | 1-2 | 150m CPU / 192Mi req → 500m / 512Mi lim |

### LiveKit Services (HPA-managed)

| Service | NodePool | Min Replicas | Max Replicas | Steady-State Pods | Resources per Pod |
|---------|----------|--------------|--------------|-------------------|-------------------|
| **livekit-server** | livekit-server | 3 | 10 | 3 | 1.5 CPU / 2Gi req → 2 CPU / 2Gi lim |
| **livekit-sip** | livekit-sip | 1 (manual) | — | 1 | 1 CPU / 1Gi req → 2 CPU / 2Gi lim |
| **livekit-egress** | livekit-egress | 5 | 30 | 5 | 3.5 CPU / 4Gi req → 4 CPU / 4Gi lim |

### Monitoring Services (Fixed replicas)

| Service | NodePool | Replicas | Resources per Pod |
|---------|----------|----------|-------------------|
| **Prometheus** | monitoring | 1 | 500m CPU / 2Gi req → 2 CPU / 4Gi lim |
| **Grafana** | monitoring | 1 | 100m CPU / 256Mi req → 500m / 512Mi lim |
| **Alertmanager** | monitoring | 1 | 50m CPU / 128Mi req → 200m / 256Mi lim |
| **Loki** | monitoring | 1 | 200m CPU / 512Mi req → 1 CPU / 2Gi lim |
| **Loki Gateway** | monitoring | 1 | 50m CPU / 64Mi req → 200m / 128Mi lim |
| **Tempo Distributor** | monitoring | 1 | 50m CPU / 128Mi req → 500m / 512Mi lim |
| **Tempo Ingester** | monitoring | 1 | 100m CPU / 512Mi req → 500m / 1Gi lim |
| **Tempo Querier** | monitoring | 1 | 50m CPU / 128Mi req → 500m / 512Mi lim |
| **Tempo Query Frontend** | monitoring | 1 | 50m CPU / 128Mi req → 500m / 512Mi lim |
| **Tempo Compactor** | monitoring | 1 | — |
| **kube-state-metrics** | monitoring | 1 | 50m CPU / 128Mi req → 200m / 256Mi lim |
| **prometheus-adapter** | monitoring | 1 | 50m CPU / 256Mi req → 200m / 512Mi lim |
| **prometheus-operator** | monitoring | 1 | 100m CPU / 256Mi req → 500m / 512Mi lim |

### DaemonSets (run on ALL nodes)

| Service | NodePool | Pods = Nodes | Resources per Pod |
|---------|----------|--------------|-------------------|
| **otel-collector** | ALL | 1 per node | 100m CPU / 256Mi req → 500m / 512Mi lim |
| **node-exporter** | ALL | 1 per node | — |

### Cluster Infrastructure (core managed node group)

| Service | NodePool | Replicas | Resources per Pod |
|---------|----------|----------|-------------------|
| **Karpenter** | core | 1 | 100m CPU / 256Mi req → 1 CPU / 1Gi lim |
| **KEDA operator** | core | 1 | 50m CPU / 128Mi req → 500m / 512Mi lim |
| **KEDA metrics-apiserver** | core | 1 | 50m CPU / 64Mi req → 250m / 256Mi lim |
| **KEDA admission-webhooks** | core | 1 | — |
| **CoreDNS** | core | 2 | EKS default |

---

## Node Count Calculation

### Steady-State (normal load)

| NodePool | Instance Type | Pods on Pool | CPU Needed | Nodes Needed | Calculation |
|----------|--------------|--------------|------------|--------------|-------------|
| **core** (managed) | t3.medium (2 vCPU) | Karpenter + KEDA + CoreDNS | ~0.5 CPU | **1 node** | EKS managed, fixed |
| **agent-voice** | c6in.xlarge (4 vCPU) | 2-5 voice pods @ 2 CPU each | 4-10 CPU | **1-3 nodes** | 2 pods/node max |
| **dev-workloads** | c6a.xlarge (4 vCPU) | 5-8 pods @ 0.1-0.5 CPU each | ~1.5 CPU total | **1 node** | All 5 services fit on 1 node |
| **monitoring** | t4g.large (2 vCPU) | 13 pods @ varied | ~1.5 CPU total | **1 node** | All monitoring fits on 1 t4g.large |
| **livekit-server** | c7g.2xlarge (8 vCPU) | 3 pods @ 1.5 CPU each | 4.5 CPU | **1 node** | 3 pods fit on 1 c7g.2xlarge |
| **livekit-sip** | c7g.xlarge (4 vCPU) | 1 pod @ 1 CPU | 1 CPU | **1 node** | 1 pod = 1 node |
| **livekit-egress** | c7g.2xlarge (8 vCPU) | 5 pods @ 3.5 CPU each | 17.5 CPU | **3 nodes** | ~2 pods/node |

### Steady-State Total: **9 nodes**

| Type | Count |
|------|-------|
| Managed (core) | 1 |
| Karpenter (auto) | 8 |
| **Total** | **9** |

### Peak Load (max scaling)

| NodePool | Max Pods | CPU at Max | Nodes at Max |
|----------|----------|-----------|--------------|
| core | Fixed | Fixed | **1** |
| agent-voice | 20 @ 2 CPU | 40 CPU | **10 nodes** (4 vCPU each) |
| dev-workloads | ~25 pods | ~10 CPU | **3 nodes** |
| monitoring | Fixed | Fixed | **1-2 nodes** |
| livekit-server | 10 @ 1.5 CPU | 15 CPU | **2 nodes** |
| livekit-sip | 1 | 1 CPU | **1 node** |
| livekit-egress | 30 @ 3.5 CPU | 105 CPU → limited to 100 CPU | **13 nodes** |

### Peak Total: **~31 nodes max**

---

## Isolation Guarantee

```
┌─────────────────────────────────────────────────────────────────┐
│ convogent-voice-service NEVER shares a node with other services │
│ because agent-voice nodepool taint BLOCKS all other pods.       │
│                                                                  │
│ Only voice-service has toleration for workload=agent-voice.     │
│ This is HARD ISOLATION via NoSchedule taint.                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Independence from Reference Repo (aivar-convogent-load-test)

**This cluster is 100% independent.** We only align the CONFIGURATION PATTERN:

| Aspect | Our Cluster (bank) | Reference Cluster (loadtest) |
|--------|-------------------|------------------------------|
| AWS Account | 880335327306 | 646731024209 |
| Region | ap-south-1 | ap-south-1 |
| VPC | vpc-0f780c7c9f67a8fa3 | Different VPC |
| EKS Cluster | Own cluster | convogent-v2-loadtest |
| IAM Role | convogent-bank-karpenter-node | convogent-v2-loadtest-karpenter-node |
| Subnet Tags | `karpenter.sh/discovery: convogent-v2-loadtest` | Same tag pattern, different VPC |
| Images | ECR `273354645607` (ap-south-1) | ECR `646731024209` |
| KEDA Images | Public ECR `u7h9i3k7` | Standard ghcr.io |
| DNS | hdfcstage.convogent.ai | Different domain |

**No network connectivity, no shared resources, no IAM cross-account trust.** Pure config alignment only.

---

## Verification Status

### ✅ Verified (from our side — offline validation)

| Check | Status | How Verified |
|-------|--------|--------------|
| YAML syntax — all nodepools, nodeclasses, values files | ✅ PASS | Parsed and validated structure |
| Taint/toleration alignment — all 6 app services match their nodepool taint | ✅ PASS | Cross-checked staging/values.yaml tolerations vs nodepool taint values |
| nodeSelector/label match — deployments select correct nodepool labels | ✅ PASS | Compared nodeSelector in values.yaml with nodepool template labels |
| NodeClass references — every nodepool references an existing EC2NodeClass | ✅ PASS | agent-voice→default, dev-workloads→default, monitoring→default, livekit-server→livekit-private, livekit-sip→livekit-public, livekit-egress→livekit-egress |
| KEDA custom-values.yaml — valid Helm override structure | ✅ PASS | Matches KEDA chart values.yaml schema |
| KEDA images accessible — pushed to public ECR | ✅ PASS | `docker push` succeeded, repos are public |
| Config pattern matches reference repo (feat/loadtest) | ✅ PASS | Side-by-side comparison of all 6 nodepools, 4 nodeclasses |
| No cross-cluster references — all configs self-contained | ✅ PASS | No references to account 646731024209 or convogent-v2-loadtest cluster endpoint |
| Disruption policies aligned | ✅ PASS | livekit-egress=WhenEmpty, others=WhenEmptyOrUnderutilized |
| Instance types exist in ap-south-1 | ✅ PASS | c6in, c5n, c7g, t4g, m7g all available in ap-south-1 |

### ⚠️ Needs Verification (on the actual EKS cluster — cannot test offline)

| Check | What to Verify | Command |
|-------|---------------|---------|
| EKS managed node group has `NodeGroupType: core` label | Core node must have this label for KEDA/Karpenter scheduling | `kubectl get nodes -l NodeGroupType=core` |
| Subnet tags exist in VPC | `karpenter.sh/discovery: convogent-v2-loadtest` and `kubernetes.io/role/internal-elb: "1"` | Check VPC subnet tags in AWS Console |
| SIP public subnet tag | `karpenter.sh/discovery/sip: convogent-v2-loadtest` on public subnets | Check VPC subnet tags in AWS Console |
| Security group tags | `karpenter.sh/discovery: convogent-v2-loadtest` and `livekit/node-sg: "true"` | Check SG tags in AWS Console |
| IAM role exists | `convogent-bank-karpenter-node` role must exist for Karpenter nodes | `aws iam get-role --role-name convogent-bank-karpenter-node` |
| Karpenter controller running | Karpenter must be installed and running before applying nodepools | `kubectl get pods -n karpenter` |
| KEDA install works | Helm install with custom-values.yaml pulls images from public ECR | `helm install keda ./addons/keda -f ./addons/keda/custom-values.yaml -n keda --create-namespace` |
| KEDA pods running | All 3 KEDA pods should be Running | `kubectl get pods -n keda` |
| NodePool applied | Apply all nodepool YAMLs and verify Karpenter accepts them | `kubectl apply -f addons/karpenter/nodepools/` |
| NodeClass applied | Apply all nodeclass YAMLs | `kubectl apply -f addons/karpenter/nodeclass/ && kubectl apply -f addons/karpenter/ec2nodeclass.yaml` |
| Node provisioning | Deploy a test pod with correct toleration, verify Karpenter provisions a node | `kubectl get nodeclaims` |
| gp3 StorageClass exists | Monitoring PVCs need `gp3` StorageClass | `kubectl get sc gp3` |
| LiveKit images accessible | ECR `273354645607.dkr.ecr.ap-south-1.amazonaws.com` reachable from EKS nodes | Deploy livekit-server and check pod status |
| Service images accessible | ECR `public.ecr.aws/q7j2m2s0` reachable for app service images | Deploy any service and check ImagePullBackOff |

### 🔁 Post-Deployment Validation Checklist

```bash
# 1. Verify KEDA
kubectl get pods -n keda
# Expected: 3 pods Running (operator, metrics-apiserver, admission-webhooks)

# 2. Verify Karpenter sees our nodepools
kubectl get nodepools
# Expected: 6 nodepools (agent-voice, dev-workloads, monitoring, livekit-server, livekit-sip, livekit-egress)

# 3. Verify nodeclasses
kubectl get ec2nodeclasses
# Expected: 4 classes (default, livekit-private, livekit-public, livekit-egress)

# 4. Deploy one service and check node provisioning
kubectl scale deployment convogentv2-frontend-stage --replicas=1 -n stage
# Wait 30-60s, then:
kubectl get nodes -l NodeGroupType=dev-workloads
# Expected: 1 new node provisioned by Karpenter

# 5. Verify voice-service isolation
kubectl scale deployment convogentv2-voice-stage --replicas=1 -n stage
kubectl get nodes -l NodeGroupType=agent-voice
# Expected: Separate node from dev-workloads

# 6. Verify monitoring nodepool
kubectl get nodes -l NodeGroupType=monitoring
# Expected: 1 node in ap-south-1b after monitoring stack deployed

# 7. Check no pods in Pending state
kubectl get pods --all-namespaces --field-selector=status.phase=Pending
# Expected: No pending pods (if pending, check nodepool limits/taints)
```
