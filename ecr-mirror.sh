#!/bin/bash
set -e

# Configuration
SOURCE_REGISTRY="public.ecr.aws/i3s3o0q6"
TARGET_ACCOUNT="273354645607"
TARGET_REGION="ap-south-1"
TARGET_REGISTRY="${TARGET_ACCOUNT}.dkr.ecr.${TARGET_REGION}.amazonaws.com"

# Images to mirror (repo:tag)
IMAGES=(
  "prometheus:v3.3.1"
  "prometheus-operator:v0.82.0"
  "alertmanager:v0.28.1"
  "grafana:12.0.0"
  "k8s-sidecar:1.30.0"
  "node-exporter:v1.9.1"
  "kube-state-metrics:v2.15.0"
  "loki:3.3.2"
  "nginx-unprivileged:1.27-alpine"
  "tempo:2.9.0"
  "otel-collector-contrib:0.118.0"
  "prometheus-adapter:v0.12.0"
  "prometheus-config-reloader:v0.82.0"
  "busybox:1.31.1"
)

echo "============================================"
echo "  ECR Mirror Script"
echo "  Source: ${SOURCE_REGISTRY}"
echo "  Target: ${TARGET_REGISTRY}"
echo "============================================"
echo ""

# Login to target ECR (private)
echo ">>> Logging in to target ECR (${TARGET_REGISTRY})..."
aws ecr get-login-password --region "${TARGET_REGION}" | docker login --username AWS --password-stdin "${TARGET_REGISTRY}"
echo ""

for IMAGE in "${IMAGES[@]}"; do
  REPO="${IMAGE%%:*}"
  TAG="${IMAGE##*:}"

  echo "--------------------------------------------"
  echo "Processing: ${REPO}:${TAG}"
  echo "--------------------------------------------"

  # Step 1: Create ECR repository if it doesn't exist
  echo "  [1/4] Creating ECR repo: ${REPO}"
  aws ecr create-repository \
    --repository-name "${REPO}" \
    --region "${TARGET_REGION}" 2>/dev/null && echo "       Created." || echo "       Already exists."

  # Step 2: Pull from public ECR
  echo "  [2/4] Pulling ${SOURCE_REGISTRY}/${REPO}:${TAG}"
  docker pull --platform linux/amd64 "${SOURCE_REGISTRY}/${REPO}:${TAG}"

  # Step 3: Tag for target ECR
  echo "  [3/4] Tagging -> ${TARGET_REGISTRY}/${REPO}:${TAG}"
  docker tag "${SOURCE_REGISTRY}/${REPO}:${TAG}" "${TARGET_REGISTRY}/${REPO}:${TAG}"

  # Step 4: Push to target ECR
  echo "  [4/4] Pushing ${TARGET_REGISTRY}/${REPO}:${TAG}"
  docker push "${TARGET_REGISTRY}/${REPO}:${TAG}"

  echo "  Done: ${REPO}:${TAG}"
  echo ""
done

echo "============================================"
echo "  All images pushed successfully!"
echo "============================================"
echo ""
echo "Images available at:"
for IMAGE in "${IMAGES[@]}"; do
  REPO="${IMAGE%%:*}"
  TAG="${IMAGE##*:}"
  echo "  ${TARGET_REGISTRY}/${REPO}:${TAG}"
done
