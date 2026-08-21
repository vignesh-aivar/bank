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

| Config | Reference Repo | Our Repo (Current) | Action Needed |
|--------|---------------|-------------------|---------------|
| NodePool name for shared services | `dev-workloads` | `app-workloads` | ⚠️ RENAME to `dev-workloads` |
| Taint value for shared services | `dev-workloads` | `app` | ⚠️ CHANGE to `dev-workloads` |
| Label for shared services | `NodeGroupType: dev-workloads` | `NodeGroupType: app` | ⚠️ CHANGE to `dev-workloads` |
| Monitoring nodepool | ✅ Present | ❌ MISSING | ⚠️ ADD monitoring nodepool |
| agent-voice instance family | c6in, c5n, c6a, c6i | c6a, c6i, m6a, m6i | ⚠️ ALIGN to c6in, c5n, c6a, c6i |
| agent-voice instance size | xlarge only | xlarge, 2xlarge | ⚠️ CHANGE to xlarge only |
| livekit-egress capacity type | on-demand only | spot + on-demand | ⚠️ CHANGE to on-demand only |
| livekit-egress disruption | WhenEmpty | WhenEmptyOrUnderutilized | ⚠️ CHANGE to WhenEmpty |
| livekit-egress instance type | c7g.2xlarge only | c7g.xlarge, c7g.2xlarge | ⚠️ CHANGE to c7g.2xlarge only |
| livekit-server AZ pin | NOT pinned | ap-south-1a | Keep as-is (our cluster needs this) |
| KEDA nodeSelector | `NodeGroupType: core` | Not configured yet | ⚠️ ADD to custom-values.yaml |
| Karpenter nodeSelector | `NodeGroupType: core` | Not deployed in our repo | N/A (EKS managed) |

---

## Fixes Required

1. **Rename `app-workloads` nodepool → `dev-workloads`** (align with reference)
2. **Update taint: `workload=app` → `workload=dev-workloads`**
3. **Update label: `NodeGroupType: app` → `NodeGroupType: dev-workloads`**
4. **Add `monitoring` nodepool** (t4g/m7g, arm64, on-demand, ap-south-1b)
5. **Fix agent-voice:** instance family → c6in, c5n, c6a, c6i; size → xlarge only
6. **Fix livekit-egress:** capacity → on-demand only; disruption → WhenEmpty; instance → c7g.2xlarge only
7. **Update staging values.yaml:** Change all 5 shared services nodeSelector/toleration from `dev-workloads` (already correct in staging values)
8. **Add KEDA nodeSelector** to `addons/keda/custom-values.yaml` → `NodeGroupType: core`

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

## Summary of Node Count (Expected at Steady State)

| NodePool | Expected Nodes | Reason |
|----------|---------------|--------|
| core (managed) | 1 | Fixed, always running |
| agent-voice | 1-5 | Scales with call volume |
| dev-workloads | 1-3 | 5 services bin-packed |
| monitoring | 1-2 | PVCs keep pods sticky |
| livekit-server | 1-3 | Scales with rooms |
| livekit-sip | 1 | Low traffic, single node |
| livekit-egress | 1-5 | Scales with recordings |
| **TOTAL** | **7-20** | |
