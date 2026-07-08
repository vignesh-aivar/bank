# ALB Ingress Controller — Air-Gapped Installation

## Overview

The bank EKS cluster cannot pull public images. This guide covers:
1. Pulling the image on your machine
2. Pushing to your public ECR (intermediate)
3. Pulling from bank VM and pushing to bank's private ECR
4. Installing the chart with the re-pointed image

---

## Image Required

| Image | Source | Tag |
|-------|--------|-----|
| aws-load-balancer-controller | `public.ecr.aws/eks/aws-load-balancer-controller` | `v3.4.1` |

---

## Step 1: Pull Image on Your Machine (internet access)

```bash
docker pull public.ecr.aws/eks/aws-load-balancer-controller:v3.4.1
```

---

## Step 2: Tag and Push to Your Public ECR (intermediate repo)

```bash
# Authenticate to your ECR
aws ecr-public get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin public.ecr.aws/<YOUR_PUBLIC_ECR_ALIAS>

# Tag
docker tag public.ecr.aws/eks/aws-load-balancer-controller:v3.4.1 \
  public.ecr.aws/<YOUR_PUBLIC_ECR_ALIAS>/aws-load-balancer-controller:v3.4.1

# Push
docker push public.ecr.aws/<YOUR_PUBLIC_ECR_ALIAS>/aws-load-balancer-controller:v3.4.1
```

---

## Step 3: On the Bank VM — Pull from Your Public ECR and Push to Bank's Private ECR

```bash
# Pull from your public ECR
docker pull public.ecr.aws/<YOUR_PUBLIC_ECR_ALIAS>/aws-load-balancer-controller:v3.4.1

# Authenticate to bank's private ECR
aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin 273354645607.dkr.ecr.ap-south-1.amazonaws.com

# Create repo in bank ECR (one time)
aws ecr create-repository \
  --repository-name aws-load-balancer-controller \
  --region ap-south-1

# Tag for bank's ECR
docker tag public.ecr.aws/<YOUR_PUBLIC_ECR_ALIAS>/aws-load-balancer-controller:v3.4.1 \
  273354645607.dkr.ecr.ap-south-1.amazonaws.com/aws-load-balancer-controller:v3.4.1

# Push to bank's ECR
docker push 273354645607.dkr.ecr.ap-south-1.amazonaws.com/aws-load-balancer-controller:v3.4.1
```

---

## Step 4: Create IAM Policy for ALB Controller

```bash
# Download the IAM policy
# (do this on your machine with internet, include the JSON file in the repo)
curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.11.0/docs/install/iam_policy.json

# Create the policy in bank AWS account
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam-policy.json \
  --region ap-south-1
```

---

## Step 5: Create IAM Role and Pod Identity Association

```bash
# Create IAM role with Pod Identity trust
aws iam create-role \
  --role-name AWSLoadBalancerControllerRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {
        "Service": "pods.eks.amazonaws.com"
      },
      "Action": ["sts:AssumeRole", "sts:TagSession"]
    }]
  }'

# Attach policy
aws iam attach-role-policy \
  --role-name AWSLoadBalancerControllerRole \
  --policy-arn arn:aws:iam::273354645607:policy/AWSLoadBalancerControllerIAMPolicy

# Create Pod Identity Association
aws eks create-pod-identity-association \
  --cluster-name <CLUSTER_NAME> \
  --namespace kube-system \
  --service-account aws-load-balancer-controller \
  --role-arn arn:aws:iam::273354645607:role/AWSLoadBalancerControllerRole
```

---

## Step 6: Install the Chart

```bash
cd addons

# Extract the chart
tar -xzf aws-load-balancer-controller-3.4.1.tgz

# Install with custom values (image pointing to bank ECR)
helm upgrade --install aws-load-balancer-controller ./aws-load-balancer-controller \
  -f alb-ingress-controller-values.yaml \
  -n kube-system
```

---

## Step 7: Verify

```bash
kubectl get deployment aws-load-balancer-controller -n kube-system
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

---

## Placeholders to Replace

| Placeholder | Description |
|-------------|-------------|
| `<CLUSTER_NAME>` | EKS cluster name |
| `<VPC_ID>` | VPC ID where the cluster runs |
| `<YOUR_PUBLIC_ECR_ALIAS>` | Your intermediate public ECR alias for image transfer |
