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
  --from-run   Previous run ID to resume from (default: latest)
  --model      Model ID (default: claude-sonnet-4-20250514)
  --region     AWS region (default: eu-west-1)
  --help       Show this help
EOF
  exit 0
}

PROJECT="" CODE_PATH="" STAGE="parse" FROM_RUN="" MODEL="" REGION="eu-west-1"

while [[ $# -gt 0 ]]; do
  case $1 in
    --project) PROJECT="$2"; shift 2;;
    --code) CODE_PATH="$2"; shift 2;;
    --stage) STAGE="$2"; shift 2;;
    --from-run) FROM_RUN="$2"; shift 2;;
    --model) MODEL="$2"; shift 2;;
    --region) REGION="$2"; shift 2;;
    --help) usage;;
    *) echo "Unknown option: $1"; usage;;
  esac
done

[[ -z "$PROJECT" ]] && { echo "Error: --project required"; usage; }
[[ -z "$CODE_PATH" && "$STAGE" == "parse" ]] && { echo "Error: --code required for parse stage"; usage; }

# Resolve Terraform outputs
INFRA_DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"
BUCKET=$(terraform -chdir="$INFRA_DIR" output -raw bucket_name)
CLUSTER=$(terraform -chdir="$INFRA_DIR" output -raw ecs_cluster_name)
TASK_DEF=$(terraform -chdir="$INFRA_DIR" output -raw task_definition_arn)
SUBNET=$(terraform -chdir="$INFRA_DIR" output -raw subnet_id)
SG=$(terraform -chdir="$INFRA_DIR" output -raw security_group_id)

RUN_ID="run-$(date +%Y%m%dT%H%M%S)-$(openssl rand -hex 4)"

# If stage != parse and no --from-run, find latest run
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

# Upload code if provided
if [[ -n "$CODE_PATH" ]]; then
  echo "==> Uploading code to s3://${BUCKET}/projects/${PROJECT}/${RUN_ID}/input/"
  aws s3 sync "$CODE_PATH" "s3://${BUCKET}/projects/${PROJECT}/${RUN_ID}/input/" --quiet --region "$REGION"
fi

# Copy previous run outputs if resuming
if [[ -n "$FROM_RUN" && "$FROM_RUN" != "$RUN_ID" ]]; then
  echo "==> Copying previous outputs from ${FROM_RUN} to ${RUN_ID}"
  aws s3 sync "s3://${BUCKET}/projects/${PROJECT}/${FROM_RUN}/" \
    "s3://${BUCKET}/projects/${PROJECT}/${RUN_ID}/" \
    --exclude "input/*" --quiet --region "$REGION"
fi

echo "==> Launching ECS task (project=${PROJECT}, run=${RUN_ID}, stage=${STAGE})"

ENV_VARS="[
  {\"name\":\"PROJECT_PATH\",\"value\":\"${PROJECT}\"},
  {\"name\":\"RUN_ID\",\"value\":\"${RUN_ID}\"},
  {\"name\":\"STAGE\",\"value\":\"${STAGE}\"}
"
[ -n "$MODEL" ] && ENV_VARS="${ENV_VARS},{\"name\":\"MODEL_ID\",\"value\":\"${MODEL}\"}"
ENV_VARS="${ENV_VARS}]"

OVERRIDES="{\"containerOverrides\":[{\"name\":\"agent\",\"environment\":${ENV_VARS}}]}"

TASK_ARN=$(aws ecs run-task \
  --region "$REGION" \
  --cluster "$CLUSTER" \
  --task-definition "$TASK_DEF" \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET],securityGroups=[$SG],assignPublicIp=ENABLED}" \
  --overrides "$OVERRIDES" \
  --query 'tasks[0].taskArn' --output text)

echo "==> Task started: ${TASK_ARN}"
echo "==> Run ID: ${RUN_ID}"
echo "==> Results: s3://${BUCKET}/projects/${PROJECT}/${RUN_ID}/"
echo "==> Logs: aws logs tail /ecs/openant --follow"
echo ""
echo "To run next step:"
echo "  $0 --project ${PROJECT} --stage <next-stage> --from-run ${RUN_ID}"
echo ""
echo "To download results:"
echo "  ./scripts/download.sh --project ${PROJECT} --run-id ${RUN_ID} --task-arn ${TASK_ARN}"
