#!/usr/bin/env bash
set -euo pipefail

JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --json) JSON_OUTPUT=true; shift;;
    *) echo "Unknown option: $1"; exit 1;;
  esac
done

START_TIME=$(date +%s)

INFRA_DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"
REGISTRY_URL=$(terraform -chdir="$INFRA_DIR" output -raw artifact_registry_url)
REGION=$(echo "$REGISTRY_URL" | cut -d'-' -f1-2)

# Login to Artifact Registry
$JSON_OUTPUT || echo "==> Logging in to Artifact Registry..."
if ! gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet 2>/dev/null; then
  if $JSON_OUTPUT; then
    echo "{\"success\":false,\"error\":\"Artifact Registry login failed\",\"stage\":\"login\"}"
  else
    echo "ERROR: Artifact Registry login failed"
  fi
  exit 1
fi

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
IMAGE="${REGISTRY_URL}/agent:latest"
$JSON_OUTPUT || echo "==> Pushing to ${IMAGE}"
docker tag openant-agent:latest "$IMAGE"
if ! docker push "$IMAGE" >/dev/null 2>&1; then
  if $JSON_OUTPUT; then
    echo "{\"success\":false,\"error\":\"Docker push failed\",\"stage\":\"push\"}"
  else
    echo "ERROR: Docker push failed"
  fi
  exit 1
fi

# Get digest
DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$IMAGE" 2>/dev/null | cut -d'@' -f2 || echo "unknown")

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

if $JSON_OUTPUT; then
  cat <<EOF
{"success":true,"image":"${IMAGE}","digest":"${DIGEST}","duration_seconds":${DURATION}}
EOF
else
  echo "==> Done. Duration: ${DURATION}s | Digest: ${DIGEST}"
fi
