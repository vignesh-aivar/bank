# Monitoring Stack — Air-Gapped Bank EKS Installation

## Overview

Full Grafana LGTM stack (Prometheus + Grafana + Loki + Tempo + OTel Collector) deployed in `monitoring` namespace, pinned to dedicated monitoring node group.

---

## Images Required

| Component | Image | ECR Repo Name |
|-----------|-------|---------------|
| Prometheus | `quay.io/prometheus/prometheus` | `prometheus` |
| Prometheus Operator | `quay.io/prometheus-operator/prometheus-operator` | `prometheus-operator` |
| Alertmanager | `quay.io/prometheus/alertmanager` | `alertmanager` |
| Grafana | `docker.io/grafana/grafana` | `grafana` |
| Grafana Sidecar | `quay.io/kiwigrid/k8s-sidecar` | `k8s-sidecar` |
| kube-state-metrics | `registry.k8s.io/kube-state-metrics/kube-state-metrics` | `kube-state-metrics` |
| Node Exporter | `quay.io/prometheus/node-exporter` | `node-exporter` |
| Loki | `docker.io/grafana/loki` | `loki` |
| Loki Gateway (nginx) | `docker.io/nginxinc/nginx-unprivileged` | `nginx-unprivileged` |
| Tempo | `docker.io/grafana/tempo` | `tempo` |
| OTel Collector | `ghcr.io/open-telemetry/opentelemetry-collector-releases/opentelemetry-collector-contrib` | `otel-collector-contrib` |
| Prometheus Adapter | `registry.k8s.io/prometheus-adapter/prometheus-adapter` | `prometheus-adapter` |
| Config Reloader | `quay.io/prometheus-operator/prometheus-config-reloader` | `prometheus-config-reloader` |

---

## Step 1: Create Monitoring Node Group

```bash
aws eks create-nodegroup \
  --cluster-name <CLUSTER_NAME> \
  --nodegroup-name convogent-monitoring \
  --node-role arn:aws:iam::273354645607:role/<NODE_ROLE_NAME> \
  --instance-types c6a.2xlarge \
  --scaling-config minSize=1,maxSize=3,desiredSize=2 \
  --ami-type AL2023_x86_64_STANDARD \
  --capacity-type ON_DEMAND \
  --disk-size 100 \
  --subnets <SUBNET_1> <SUBNET_2> <SUBNET_3> \
  --labels NodeGroupType=monitoring \
  --taints "key=workload,value=monitoring,effect=NO_SCHEDULE" \
  --tags Environment=production,Service=convogent,NodeGroup=monitoring
```

---

## Step 2: Push Images to Bank ECR

```bash
# Create repos (one-time)
for repo in prometheus prometheus-operator alertmanager grafana k8s-sidecar \
  kube-state-metrics node-exporter loki nginx-unprivileged tempo \
  otel-collector-contrib prometheus-adapter prometheus-config-reloader; do
  aws ecr create-repository --repository-name $repo --region ap-south-1
done
```

Pull from your public ECR, tag, and push to `273354645607.dkr.ecr.ap-south-1.amazonaws.com/<repo>:<tag>` (same relay process as ALB/LiveKit).

---

## Step 3: Create Tempo S3 Bucket + IAM

```bash
# Create S3 bucket for traces
aws s3 mb s3://<S3_TRACES_BUCKET> --region ap-south-1

# Create IAM role for Tempo (Pod Identity)
aws iam create-role \
  --role-name ConvogentTempoRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": { "Service": "pods.eks.amazonaws.com" },
      "Action": ["sts:AssumeRole", "sts:TagSession"]
    }]
  }'

# Attach S3 policy
aws iam put-role-policy \
  --role-name ConvogentTempoRole \
  --policy-name tempo-s3 \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket","s3:GetBucketLocation"],
      "Resource": ["arn:aws:s3:::<S3_TRACES_BUCKET>","arn:aws:s3:::<S3_TRACES_BUCKET>/*"]
    }]
  }'

# Pod Identity Association
aws eks create-pod-identity-association \
  --cluster-name <CLUSTER_NAME> \
  --namespace monitoring \
  --service-account tempo \
  --role-arn arn:aws:iam::273354645607:role/ConvogentTempoRole
```

---

## Step 4: Deploy (install order matters)

```bash
cd addons/monitoring

# Extract all charts
tar -xzf kube-prometheus-stack-72.3.0.tgz
tar -xzf loki-6.24.0.tgz
tar -xzf tempo-distributed-1.61.3.tgz
tar -xzf opentelemetry-collector-0.115.0.tgz
tar -xzf prometheus-adapter-4.11.0.tgz

# 1. Prometheus + Grafana (installs CRDs first)
helm upgrade --install prometheus ./kube-prometheus-stack \
  -f kube-prometheus-stack-values.yaml \
  -n monitoring --create-namespace

# 2. Loki (log backend)
helm upgrade --install loki ./loki \
  -f loki-values.yaml \
  -n monitoring

# 3. Tempo (trace backend)
helm upgrade --install tempo ./tempo-distributed \
  -f tempo-values.yaml \
  -n monitoring

# 4. OTel Collector (log/trace pipeline)
helm upgrade --install otel-collector ./opentelemetry-collector \
  -f otel-collector-values.yaml \
  -n monitoring

# 5. Prometheus Adapter (custom HPA metrics for LiveKit egress)
helm upgrade --install prometheus-adapter ./prometheus-adapter \
  -f prometheus-adapter-values.yaml \
  -n monitoring
```

---

## Step 5: Verify

```bash
kubectl get pods -n monitoring
kubectl get svc -n monitoring
kubectl get pvc -n monitoring
kubectl get servicemonitors -n monitoring
```

---

## Placeholders

| Placeholder | Where | Description |
|-------------|-------|-------------|
| `<CLUSTER_NAME>` | Node group + Pod Identity | EKS cluster name |
| `<S3_TRACES_BUCKET>` | tempo-values.yaml + IAM | S3 bucket for Tempo traces |

---

## Node Group Summary (all 4)

| Node Group | Label | Taint | Purpose |
|-----------|-------|-------|---------|
| `convogent-app` | `NodeGroupType=app` | `workload=app:NoSchedule` | Frontend, backend, chat, eval, pca |
| `convogent-agent-voice` | `NodeGroupType=agent-voice` | `workload=agent-voice:NoSchedule` | Voice service |
| `livekit-core` | `workload=livekit-core` | `workload=livekit-core:NoSchedule` | LiveKit server + egress |
| `convogent-monitoring` | `NodeGroupType=monitoring` | `workload=monitoring:NoSchedule` | Prometheus, Grafana, Loki, Tempo, OTel, Adapter |
