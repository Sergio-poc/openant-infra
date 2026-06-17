#!/usr/bin/env bash
set -euo pipefail

REGION="eu-west-1"
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --json) JSON_OUTPUT=true; shift;;
    --region) REGION="$2"; shift 2;;
    *) REGION="$1"; shift;;
  esac
done

START_TIME=$(date +%s)

INFRA_DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"
ECR_URL=$(terraform -chdir="$INFRA_DIR" output -raw ecr_repository_url)
ACCOUNT=$(echo "$ECR_URL" | cut -d'.' -f1)

# Login
$JSON_OUTPUT || echo "==> Logging in to ECR..."
aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com" >/dev/null 2>&1 || {
    if $JSON_OUTPUT; then
      echo "{\"success\":false,\"error\":\"ECR login failed\",\"stage\":\"login\"}"
    else
      echo "ERROR: ECR login failed"
    fi
    exit 1
  }

# Build
DOCKER_DIR="$(cd "$(dirname "$0")/../docker" && pwd)"
CONTEXT="$(cd "$(dirname "$0")/../.." && pwd)"

$JSON_OUTPUT || echo "==> Building image..."
if ! docker build --platform linux/amd64 -t openant-agent -f "${DOCKER_DIR}/Dockerfile" "$CONTEXT" >/dev/null 2>&1; then
  if $JSON_OUTPUT; then
    echo "{\"success\":false,\"error\":\"Docker build failed\",\"stage\":\"build\"}"
  else
    echo "ERROR: Docker build failed"
  fi
  exit 1
fi

# Push
$JSON_OUTPUT || echo "==> Pushing to ${ECR_URL}:latest"
docker tag openant-agent:latest "${ECR_URL}:latest"
if ! docker push "${ECR_URL}:latest" >/dev/null 2>&1; then
  if $JSON_OUTPUT; then
    echo "{\"success\":false,\"error\":\"Docker push failed\",\"stage\":\"push\"}"
  else
    echo "ERROR: Docker push failed"
  fi
  exit 1
fi

# Get digest
DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "${ECR_URL}:latest" 2>/dev/null | cut -d'@' -f2 || echo "unknown")

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

if $JSON_OUTPUT; then
  cat <<EOF
{"success":true,"ecr_url":"${ECR_URL}:latest","digest":"${DIGEST}","duration_seconds":${DURATION}}
EOF
else
  echo "==> Done. Duration: ${DURATION}s | Digest: ${DIGEST}"
fi
