#!/usr/bin/env bash
set -euo pipefail

REGION="${1:-eu-west-1}"

INFRA_DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"
ECR_URL=$(terraform -chdir="$INFRA_DIR" output -raw ecr_repository_url)
ACCOUNT=$(echo "$ECR_URL" | cut -d'.' -f1)

echo "==> Logging in to ECR..."
aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

DOCKER_DIR="$(cd "$(dirname "$0")/../docker" && pwd)"
CONTEXT="$(cd "$(dirname "$0")/../.." && pwd)"

echo "==> Building image..."
docker build --platform linux/amd64 -t openant-agent -f "${DOCKER_DIR}/Dockerfile" "$CONTEXT"

echo "==> Pushing to ${ECR_URL}:latest"
docker tag openant-agent:latest "${ECR_URL}:latest"
docker push "${ECR_URL}:latest"

echo "==> Done."
