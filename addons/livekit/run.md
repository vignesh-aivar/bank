# LiveKit Deployment Instructions

## Images

All LiveKit components use public ECR images from:

| Component | Image |
|-----------|-------|
| LiveKit Server | `public.ecr.aws/u7h9i3k7/livekit/livekit-server:latest` |
| LiveKit Egress | `public.ecr.aws/u7h9i3k7/livekit/livekit-egress:latest` |
| LiveKit SIP | `public.ecr.aws/u7h9i3k7/livekit/livekit-sip:latest` |

## Node Pools

Each component is scheduled on a dedicated node pool via `nodeSelector` and `tolerations`:

| Component | nodeSelector | Toleration |
|-----------|-------------|------------|
| LiveKit Server | `workload: livekit-server` | `workload=livekit-server:NoSchedule` |
| LiveKit Egress | `workload: livekit-egress` | `workload=livekit-egress:NoSchedule` |
| LiveKit SIP | `workload: livekit-sip` | `workload=livekit-sip:NoSchedule` |

## Installation

### 1. Install LiveKit Server (Helm)

```bash
helm upgrade --install livekit-server livekit/livekit-server \
  --namespace livekit --create-namespace \
  -f livekit-server-values.yaml
```

### 2. Install LiveKit Egress (Helm)

```bash
helm upgrade --install livekit-egress livekit/livekit-egress \
  --namespace livekit --create-namespace \
  -f livekit-egress-values.yaml
```

### 3. Deploy LiveKit SIP (kubectl)

```bash
kubectl apply -f sip-manifests/
```

> **Note:** The SIP deployment starts with `replicas: 0`. Scale up when ready:
> ```bash
> kubectl scale deployment livekit-sip -n livekit --replicas=1
> ```

## Verification

### Check all pods are running

```bash
kubectl get pods -n livekit -o wide
```

### Verify images in use

```bash
kubectl get pods -n livekit -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'
```

### Check node placement

```bash
kubectl get pods -n livekit -o wide | awk '{print $1, $7}'
```

### Verify LiveKit Server health

```bash
kubectl port-forward svc/livekit-server 8080:80 -n livekit &
curl http://localhost:8080
```

### Check Egress connectivity

```bash
kubectl logs -l app.kubernetes.io/name=livekit-egress -n livekit --tail=20
```

### Check SIP status

```bash
kubectl logs -l app=livekit-sip -n livekit --tail=20
```
