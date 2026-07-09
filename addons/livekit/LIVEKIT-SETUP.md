# LiveKit — Air-Gapped Bank EKS Installation

## Images Required

| Image | Source (public) | Bank ECR repo | Tag |
|-------|----------------|---------------|-----|
| livekit-server | `livekit/livekit-server` | `livekit-server` | `v1.9.12` |
| livekit-egress | `livekit/egress` | `livekit-egress` | `v1.8.4` |
| livekit-sip | `livekit/sip` | `livekit-sip` | `latest` |

---

## Step 1: Pull Images (on your machine)

```bash
docker pull livekit/livekit-server:v1.9.12
docker pull livekit/egress:v1.8.4
docker pull livekit/sip:latest
```

---

## Step 2: Push to Your Intermediate ECR

```bash
# Tag
docker tag livekit/livekit-server:v1.9.12 public.ecr.aws/<YOUR_ALIAS>/livekit-server:v1.9.12
docker tag livekit/egress:v1.8.4 public.ecr.aws/<YOUR_ALIAS>/livekit-egress:v1.8.4
docker tag livekit/sip:latest public.ecr.aws/<YOUR_ALIAS>/livekit-sip:latest

# Push
docker push public.ecr.aws/<YOUR_ALIAS>/livekit-server:v1.9.12
docker push public.ecr.aws/<YOUR_ALIAS>/livekit-egress:v1.8.4
docker push public.ecr.aws/<YOUR_ALIAS>/livekit-sip:latest
```

---

## Step 3: On Bank VM — Push to Bank's Private ECR

```bash
# Auth
aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin 273354645607.dkr.ecr.ap-south-1.amazonaws.com

# Create repos (one-time)
aws ecr create-repository --repository-name livekit-server --region ap-south-1
aws ecr create-repository --repository-name livekit-egress --region ap-south-1
aws ecr create-repository --repository-name livekit-sip --region ap-south-1

# Pull from your public ECR
docker pull public.ecr.aws/<YOUR_ALIAS>/livekit-server:v1.9.12
docker pull public.ecr.aws/<YOUR_ALIAS>/livekit-egress:v1.8.4
docker pull public.ecr.aws/<YOUR_ALIAS>/livekit-sip:latest

# Tag for bank ECR
docker tag public.ecr.aws/<YOUR_ALIAS>/livekit-server:v1.9.12 \
  273354645607.dkr.ecr.ap-south-1.amazonaws.com/livekit-server:v1.9.12
docker tag public.ecr.aws/<YOUR_ALIAS>/livekit-egress:v1.8.4 \
  273354645607.dkr.ecr.ap-south-1.amazonaws.com/livekit-egress:v1.8.4
docker tag public.ecr.aws/<YOUR_ALIAS>/livekit-sip:latest \
  273354645607.dkr.ecr.ap-south-1.amazonaws.com/livekit-sip:latest

# Push
docker push 273354645607.dkr.ecr.ap-south-1.amazonaws.com/livekit-server:v1.9.12
docker push 273354645607.dkr.ecr.ap-south-1.amazonaws.com/livekit-egress:v1.8.4
docker push 273354645607.dkr.ecr.ap-south-1.amazonaws.com/livekit-sip:latest
```

---

## Step 4: Create LiveKit Node Group

```bash
aws eks create-nodegroup \
  --cluster-name <CLUSTER_NAME> \
  --nodegroup-name livekit-core \
  --node-role arn:aws:iam::273354645607:role/<NODE_ROLE_NAME> \
  --instance-types c6a.2xlarge \
  --scaling-config minSize=3,maxSize=15,desiredSize=3 \
  --ami-type AL2023_x86_64_STANDARD \
  --capacity-type ON_DEMAND \
  --disk-size 50 \
  --subnets <SUBNET_1> <SUBNET_2> \
  --labels workload=livekit-core \
  --taints "key=workload,value=livekit-core,effect=NO_SCHEDULE" \
  --tags Environment=production,Service=livekit
```

---

## Step 5: Prerequisites (Elastic IP + Redis)

### Allocate Elastic IPs for TURN NLB

```bash
aws ec2 allocate-address --domain vpc --region ap-south-1
aws ec2 allocate-address --domain vpc --region ap-south-1
# Note the AllocationId values for turn-nlb-service.yaml
```

### Redis (ElastiCache)

Create a Redis cluster (single node or cluster mode) for LiveKit.
Note the endpoint for the values files.

---

## Step 6: Deploy

### Create namespace

```bash
kubectl apply -f manifests/namespace.yaml
```

### Extract and install livekit-server

```bash
tar -xzf livekit-server-1.9.0.tgz

helm upgrade --install livekit-server ./livekit-server \
  -f livekit-server-values.yaml \
  -n livekit
```

### Extract and install livekit-egress

```bash
tar -xzf egress-1.8.4.tgz

helm upgrade --install livekit-egress ./egress \
  -f livekit-egress-values.yaml \
  -n livekit
```

### Deploy SIP (raw manifests)

```bash
kubectl apply -f sip-manifests/
```

### Deploy supporting manifests (Ingress, NLB, HPAs)

```bash
kubectl apply -f manifests/livekit-alb-ingress.yaml
kubectl apply -f manifests/turn-nlb-service.yaml
kubectl apply -f manifests/hpa-server.yaml
kubectl apply -f manifests/hpa-egress.yaml
```

---

## Step 7: Pod Identity for Egress (S3 access)

```bash
aws eks create-pod-identity-association \
  --cluster-name <CLUSTER_NAME> \
  --namespace livekit \
  --service-account livekit-egress \
  --role-arn arn:aws:iam::273354645607:role/LivekitEgressRole
```

The role needs: `s3:PutObject`, `s3:GetObject` on the recordings bucket.

---

## Step 8: Verify

```bash
kubectl get pods -n livekit
kubectl get svc -n livekit
kubectl get ingress -n livekit
kubectl get hpa -n livekit
```

---

## Placeholders to Replace

| Placeholder | Where | Description |
|-------------|-------|-------------|
| `<TURN_NLB_EIP>` | livekit-server-values.yaml | Elastic IP public address |
| `<REDIS_ENDPOINT>` | All values + sip-config | ElastiCache Redis endpoint |
| `<LIVEKIT_API_KEY>` | All values + sip-config | Generate with `livekit-cli` or use custom |
| `<LIVEKIT_API_SECRET>` | All values + sip-config | Matching secret |
| `<LIVEKIT_DOMAIN>` | egress values, sip-config, ingress | e.g. `livekit.bankdomain.com` |
| `<TURN_DOMAIN>` | livekit-server-values.yaml | e.g. `turn.bankdomain.com` |
| `<AGENT_DOMAIN>` | livekit-server-values.yaml (webhook) | Convogent voice endpoint |
| `<ACM_CERTIFICATE_ARN>` | livekit-alb-ingress.yaml | ACM cert for the domain |
| `<PUBLIC_SUBNET_1>,<PUBLIC_SUBNET_2>` | turn-nlb-service.yaml | Public subnets for NLB |
| `<EIP_ALLOC_1>,<EIP_ALLOC_2>` | turn-nlb-service.yaml | EIP allocation IDs |
| `<S3_RECORDINGS_BUCKET>` | livekit-egress-values.yaml | S3 bucket for call recordings |
| `<CLUSTER_NAME>` | Node group creation | EKS cluster name |
