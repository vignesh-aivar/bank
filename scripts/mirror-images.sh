#!/bin/bash
# Mirror public ECR images to private ECR
# Usage: ./scripts/mirror-images.sh

set -euo pipefail

PUBLIC_REGISTRY="public.ecr.aws/q7j2m2s0"
PRIVATE_REGISTRY="273354645607.dkr.ecr.ap-south-1.amazonaws.com"
REGION="ap-south-1"
TAG="latest"

# Mapping: public repo name -> private repo name
declare -A IMAGES=(
  ["convogent-backend"]="convogent-backend"
  ["convogent-chat-service"]="convogent-chat"
  ["convogent-eval-service"]="convogent-eval"
  ["convogent-frontend"]="convogent-frontend"
  ["convogent-pca-service"]="convogent-pca"
  ["convogent-voice-service"]="convogent-voice"
  ["convogent-keycloak"]="convogent-keycloak"
)

echo "==> Logging in to public ECR..."
aws ecr-public get-login-password --region us-east-1 | docker login --username AWS --password-stdin public.ecr.aws

echo "==> Logging in to private ECR..."
aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${PRIVATE_REGISTRY}"

for PUBLIC_REPO in "${!IMAGES[@]}"; do
  PRIVATE_REPO="${IMAGES[$PUBLIC_REPO]}"
  SRC="${PUBLIC_REGISTRY}/${PUBLIC_REPO}:${TAG}"
  DST="${PRIVATE_REGISTRY}/${PRIVATE_REPO}:${TAG}"

  echo ""
  echo "--- Mirroring: ${PUBLIC_REPO} -> ${PRIVATE_REPO} ---"
  echo "  Pull: ${SRC}"
  docker pull "${SRC}"

  echo "  Tag:  ${DST}"
  docker tag "${SRC}" "${DST}"

  echo "  Push: ${DST}"
  docker push "${DST}"

  echo "  Done: ${PRIVATE_REPO}:${TAG}"
done

echo ""
echo "==> All images mirrored successfully!"
