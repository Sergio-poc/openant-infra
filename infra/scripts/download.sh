#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 --project <org/repo> --run-id <id> [options]

Wait for ECS task to complete, then download results from S3.

Options:
  --project    Project path org/repo (required)
  --run-id     Run ID (required)
  --task-arn   ECS task ARN (optional — skips task lookup)
  --region     AWS region (default: eu-west-1)
  --help       Show this help
EOF
  exit 0
}

PROJECT="" RUN_ID="" TASK_ARN="" REGION="eu-west-1"

while [[ $# -gt 0 ]]; do
  case $1 in
    --project) PROJECT="$2"; shift 2;;
    --run-id) RUN_ID="$2"; shift 2;;
    --task-arn) TASK_ARN="$2"; shift 2;;
    --region) REGION="$2"; shift 2;;
    --help) usage;;
    *) echo "Unknown option: $1"; usage;;
  esac
done

[[ -z "$PROJECT" ]] && { echo "Error: --project required"; usage; }
[[ -z "$RUN_ID" ]] && { echo "Error: --run-id required"; usage; }

INFRA_DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"
BUCKET=$(terraform -chdir="$INFRA_DIR" output -raw bucket_name)
CLUSTER=$(terraform -chdir="$INFRA_DIR" output -raw ecs_cluster_name)

# Find task ARN if not provided
if [[ -z "$TASK_ARN" ]]; then
  echo "==> Looking for ECS task with RUN_ID=${RUN_ID}..."
  for status in RUNNING STOPPED; do
    TASK_ARNS=$(aws ecs list-tasks --cluster "$CLUSTER" --desired-status "$status" --region "$REGION" --query 'taskArns[]' --output text 2>/dev/null || true)
    [[ -z "$TASK_ARNS" ]] && continue
    for arn in $TASK_ARNS; do
      ENV_VAL=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$arn" --region "$REGION" \
        --query "tasks[0].overrides.containerOverrides[0].environment[?name=='RUN_ID'].value" --output text 2>/dev/null || true)
      if [[ "$ENV_VAL" == "$RUN_ID" ]]; then
        TASK_ARN="$arn"
        break 2
      fi
    done
  done
  [[ -z "$TASK_ARN" ]] && { echo "Error: could not find ECS task for run-id '${RUN_ID}'"; exit 1; }
  echo "==> Found task: ${TASK_ARN}"
fi

# Wait for task to stop
echo "==> Waiting for task to complete..."
aws ecs wait tasks-stopped --cluster "$CLUSTER" --tasks "$TASK_ARN" --region "$REGION" 2>/dev/null || true

EXIT_CODE=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" --region "$REGION" \
  --query 'tasks[0].containers[0].exitCode' --output text 2>/dev/null || echo "UNKNOWN")

if [[ "$EXIT_CODE" != "0" ]]; then
  echo "⚠️  WARNING: Task exited with status ${EXIT_CODE}. Results may be partial."
fi

# Download
DEST="./results/${PROJECT}/${RUN_ID}"
echo "==> Downloading s3://${BUCKET}/projects/${PROJECT}/${RUN_ID}/ → ${DEST}/"
mkdir -p "$DEST"
aws s3 sync "s3://${BUCKET}/projects/${PROJECT}/${RUN_ID}/" "$DEST/" --region "$REGION" --exclude "input/*"

echo "==> Download complete: ${DEST}/"
