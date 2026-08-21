# KEDA - Kubernetes Event-Driven Autoscaler

## Overview

KEDA (Kubernetes Event-Driven Autoscaling) v2.20.2 is configured to pull images from our public ECR repository, so EKS clusters can access them without any authentication or image pull secrets.

## Public ECR Repositories

All KEDA images are hosted at:

| Component | Image URI |
|-----------|-----------|
| KEDA Operator | `public.ecr.aws/u7h9i3k7/keda/keda:2.20.2` |
| Metrics API Server | `public.ecr.aws/u7h9i3k7/keda/keda-metrics-apiserver:2.20.2` |
| Admission Webhooks | `public.ecr.aws/u7h9i3k7/keda/keda-admission-webhooks:2.20.2` |

**Registry:** `public.ecr.aws/u7h9i3k7`  
**AWS Account:** `880335327306`  
**Region:** `us-east-1`

## Prerequisites

- Helm 3.x installed
- kubectl configured with your EKS cluster
- Cluster access with permissions to create namespaces and CRDs

## Installation

### 1. Install KEDA with custom values (public ECR images)

```bash
helm install keda ./addons/keda \
  -f ./addons/keda/custom-values.yaml \
  -n keda \
  --create-namespace
```

### 2. Verify installation

```bash
# Check all KEDA pods are running
kubectl get pods -n keda

# Expected output:
# keda-operator-xxxxx              1/1     Running
# keda-metrics-apiserver-xxxxx     1/1     Running
# keda-admission-webhooks-xxxxx    1/1     Running
```

### 3. Verify images are pulled from public ECR

```bash
kubectl get pods -n keda -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'
```

## Upgrade

```bash
helm upgrade keda ./addons/keda \
  -f ./addons/keda/custom-values.yaml \
  -n keda
```

## Uninstall

```bash
helm uninstall keda -n keda
kubectl delete namespace keda
```

## Custom Values Reference

The `custom-values.yaml` overrides the default image registry from `ghcr.io` to our public ECR:

```yaml
image:
  keda:
    registry: public.ecr.aws/u7h9i3k7
    repository: keda/keda
    tag: "2.20.2"
  metricsApiServer:
    registry: public.ecr.aws/u7h9i3k7
    repository: keda/keda-metrics-apiserver
    tag: "2.20.2"
  webhooks:
    registry: public.ecr.aws/u7h9i3k7
    repository: keda/keda-admission-webhooks
    tag: "2.20.2"
```

## Troubleshooting

- **ImagePullBackOff:** Ensure the EKS cluster has outbound internet access to `public.ecr.aws`
- **CRD conflicts:** If upgrading from a previous KEDA version, delete old CRDs first: `kubectl delete crd scaledobjects.keda.sh scaledjobs.keda.sh triggerauthentications.keda.sh`
- **Webhook errors:** Wait 30-60 seconds after install for webhooks to become ready
