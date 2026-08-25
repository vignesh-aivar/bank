# Karpenter Installation Guide

## Overview

Karpenter v1.3.3 is deployed on the **convogent-v2-loadtest** EKS cluster in `ap-south-1`. The controller runs on the **core** managed node group (`NodeGroupType: core`) to ensure availability independent of Karpenter-provisioned nodes.

- **Image**: `public.ecr.aws/u7h9i3k7/karpenter/controller:1.3.3`
- **Namespace**: `karpenter`
- **Node placement**: Core node group (`nodeSelector: NodeGroupType: core`)

---

## 1. Install Karpenter via OCI Helm Chart

```bash
# Create the namespace
kubectl create namespace karpenter

# Install using the OCI chart from public ECR with custom values
helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version 1.3.3 \
  -f ./addons/karpenter/custom-values.yaml \
  -n karpenter
```

To upgrade an existing installation:

```bash
helm upgrade karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version 1.3.3 \
  -f ./addons/karpenter/custom-values.yaml \
  -n karpenter
```

---

## 2. Apply NodePools and NodeClasses

After installing the Karpenter controller, apply your NodePool and EC2NodeClass resources:

```bash
# Apply EC2NodeClass (defines AMI, subnets, security groups, instance profile)
kubectl apply -f ./addons/karpenter/nodeclasses/

# Apply NodePool (defines instance types, capacity constraints, disruption policies)
kubectl apply -f ./addons/karpenter/nodepools/
```

Example directory structure:

```
addons/karpenter/
├── chart/                  # Pulled helm chart (v1.3.3)
├── custom-values.yaml      # Helm values override
├── nodeclasses/            # EC2NodeClass manifests
│   └── default.yaml
├── nodepools/              # NodePool manifests
│   └── default.yaml
└── run.md                  # This file
```

---

## 3. Verification Commands

```bash
# Check Karpenter pods are running on core nodes
kubectl get pods -n karpenter -o wide

# Verify the controller is healthy
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f

# List NodePools
kubectl get nodepools

# List EC2NodeClasses
kubectl get ec2nodeclasses

# Check nodes provisioned by Karpenter
kubectl get nodes -l karpenter.sh/registered=true

# Check Karpenter events for provisioning activity
kubectl get events -n karpenter --sort-by='.lastTimestamp'

# Verify ServiceMonitor is created (for Prometheus scraping)
kubectl get servicemonitor -n karpenter
```

---

## 4. Troubleshooting

```bash
# Check controller logs for errors
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=100

# Describe a NodePool to see status and conditions
kubectl describe nodepool <name>

# Check if the SQS interruption queue is receiving events
aws sqs get-queue-attributes \
  --queue-url https://sqs.ap-south-1.amazonaws.com/<account-id>/Karpenter-convogent-v2-loadtest \
  --attribute-names ApproximateNumberOfMessages
```

---

## Notes

- The controller is pinned to the core node group to avoid a chicken-and-egg problem where Karpenter needs to be running to provision its own nodes.
- PodDisruptionBudget ensures at least 1 replica remains available during voluntary disruptions.
- ServiceMonitor is enabled for Prometheus metrics collection (requires `release: prometheus` label match).
