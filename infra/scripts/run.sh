#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 --project <org/repo> [options]

Launch an OpenAnt pipeline step on ECS Fargate.

Options:
  --project    Project path org/repo (required)
  --code       Path to source code directory (required for parse)
  --stage      Pipeline step: parse|enhance|analyze|verify|build-output|report (default: parse)
  --pipeline   Comma-separated stages to run sequentially (e.g. parse,enhance,analyze,verify)
  --from-run   Previous run ID to resume from (default: latest)
  --model      Model ID (default: claude-sonnet-4-20250514)
  --region     AWS region (default: eu-west-1)
  --help       Show this help
EOF
  exit 0
}

PROJECT="" CODE_PATH="" STAGE="parse" FROM_RUN="" MODEL="" REGION="eu-west-1" PIPELINE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --project) PROJECT="$2"; shift 2;;
    --code) CODE_PATH="$2"; shift 2;;
    --stage) STAGE="$2"; shift 2;;
    --pipeline) PIPELINE="$2"; shift 2;;
    --from-run) FROM_RUN="$2"; shift 2;;
    --model) MODEL="$2"; shift 2;;
    --region) REGION="$2"; shift 2;;
    --help) usage;;
    *) echo "Unknown option: $1"; usage;;
  esac
done

[[ -z "$PROJECT" ]] && { echo "Error: --project required"; usage; }
[[ -z "$CODE_PATH" && "$STAGE" == "parse" && -z "$PIPELINE" ]] && { echo "Error: --code required for parse stage"; usage; }

# Resolve Terraform outputs
INFRA_DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"
BUCKET=$(terraform -chdir="$INFRA_DIR" output -raw bucket_name)
CLUSTER=$(terraform -chdir="$INFRA_DIR" output -raw ecs_cluster_name)
TASK_DEF=$(terraform -chdir="$INFRA_DIR" output -raw task_definition_arn)
SUBNET=$(terraform -chdir="$INFRA_DIR" output -raw subnet_id)
SG=$(terraform -chdir="$INFRA_DIR" output -raw security_group_id)

RUN_ID="run-$(date +%Y%m%dT%H%M%S)-$(openssl rand -hex 4)"

# --- Helper: run a single stage ---
run_stage() {
  local STAGE_NAME="$1"
  local STAGE_RUN_ID="$2"
  local STAGE_FROM_RUN="$3"
  local STAGE_START=$(date +%s)

  # Find latest run if needed
  if [[ "$STAGE_NAME" != "parse" && -z "$STAGE_FROM_RUN" ]]; then
    STAGE_FROM_RUN=$(aws s3 ls "s3://${BUCKET}/projects/${PROJECT}/" --region "$REGION" | \
      grep 'PRE run-' | awk '{print $2}' | tr -d '/' | sort | tail -1)
    [[ -z "$STAGE_FROM_RUN" ]] && { echo "Error: no previous run found."; return 1; }
  fi

  # Upload code if parse and code_path provided
  if [[ "$STAGE_NAME" == "parse" && -n "$CODE_PATH" ]]; then
    echo "==> Uploading code to s3://${BUCKET}/projects/${PROJECT}/${STAGE_RUN_ID}/input/"
    aws s3 sync "$CODE_PATH" "s3://${BUCKET}/projects/${PROJECT}/${STAGE_RUN_ID}/input/" --quiet --region "$REGION"
  fi

  # Copy previous outputs
  if [[ -n "$STAGE_FROM_RUN" && "$STAGE_FROM_RUN" != "$STAGE_RUN_ID" ]]; then
    echo "==> Copying previous outputs from ${STAGE_FROM_RUN} to ${STAGE_RUN_ID}"
    aws s3 sync "s3://${BUCKET}/projects/${PROJECT}/${STAGE_FROM_RUN}/" \
      "s3://${BUCKET}/projects/${PROJECT}/${STAGE_RUN_ID}/" \
      --exclude "input/*" --quiet --region "$REGION"
  fi

  echo "==> Launching ECS task (project=${PROJECT}, run=${STAGE_RUN_ID}, stage=${STAGE_NAME})"

  local ENV_VARS="[{\"name\":\"PROJECT_PATH\",\"value\":\"${PROJECT}\"},{\"name\":\"RUN_ID\",\"value\":\"${STAGE_RUN_ID}\"},{\"name\":\"STAGE\",\"value\":\"${STAGE_NAME}\"}"
  [ -n "$MODEL" ] && ENV_VARS="${ENV_VARS},{\"name\":\"MODEL_ID\",\"value\":\"${MODEL}\"}"
  ENV_VARS="${ENV_VARS}]"

  local OVERRIDES="{\"containerOverrides\":[{\"name\":\"agent\",\"environment\":${ENV_VARS}}]}"

  local TASK_ARN=$(aws ecs run-task \
    --region "$REGION" --cluster "$CLUSTER" --task-definition "$TASK_DEF" \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET],securityGroups=[$SG],assignPublicIp=ENABLED}" \
    --overrides "$OVERRIDES" \
    --query 'tasks[0].taskArn' --output text)

  echo "==> Task: ${TASK_ARN}"

  # Wait
  aws ecs wait tasks-stopped --cluster "$CLUSTER" --tasks "$TASK_ARN" --region "$REGION"

  local EXIT_CODE=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" --region "$REGION" \
    --query 'tasks[0].containers[0].exitCode' --output text)

  local STAGE_END=$(date +%s)
  local DURATION=$((STAGE_END - STAGE_START))

  echo "==> ${STAGE_NAME}: exit_code=${EXIT_CODE} duration=${DURATION}s"

  [[ "$EXIT_CODE" != "0" ]] && return 1
  return 0
}

# --- Pipeline mode ---
if [[ -n "$PIPELINE" ]]; then
  IFS=',' read -ra STAGES <<< "$PIPELINE"
  CURRENT_RUN="$RUN_ID"
  PIPELINE_START=$(date +%s)
  echo "==> Pipeline: ${PIPELINE} (run=${CURRENT_RUN})"
  echo ""

  for PSTAGE in "${STAGES[@]}"; do
    run_stage "$PSTAGE" "$CURRENT_RUN" "$FROM_RUN" || {
      echo ""
      echo "❌ Pipeline failed at stage: ${PSTAGE}"
      echo "==> Results so far: s3://${BUCKET}/projects/${PROJECT}/${CURRENT_RUN}/"
      exit 1
    }
    FROM_RUN="$CURRENT_RUN"
    echo ""
  done

  PIPELINE_END=$(date +%s)
  echo "✅ Pipeline complete in $((PIPELINE_END - PIPELINE_START))s"
  echo "==> Run ID: ${CURRENT_RUN}"
  echo "==> Results: s3://${BUCKET}/projects/${PROJECT}/${CURRENT_RUN}/"
  exit 0
fi

# --- Single stage mode (original behavior) ---
if [[ "$STAGE" != "parse" && -z "$FROM_RUN" ]]; then
  echo "==> Finding latest run for project: ${PROJECT}"
  FROM_RUN=$(aws s3 ls "s3://${BUCKET}/projects/${PROJECT}/" --region "$REGION" | \
    grep 'PRE run-' | awk '{print $2}' | tr -d '/' | sort | tail -1)
  if [[ -z "$FROM_RUN" ]]; then
    echo "Error: no previous run found. Run parse first."
    exit 1
  fi
  echo "==> Using from-run: ${FROM_RUN}"
fi

run_stage "$STAGE" "$RUN_ID" "$FROM_RUN"

echo ""
echo "==> Run ID: ${RUN_ID}"
echo "==> Results: s3://${BUCKET}/projects/${PROJECT}/${RUN_ID}/"
echo "==> Logs: aws logs tail /ecs/openant --follow"
